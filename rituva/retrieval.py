"""Grounded hybrid retrieval (RAG) over the cited guideline rules and the recipe
corpus (PRD §9.7).

Two channels are fused with Reciprocal Rank Fusion (RRF):
  * sparse — pure-Python BM25 (keyword relevance), and
  * dense  — pure-Python TF-IDF cosine similarity (semantic-ish stand-in so the
             stack runs with zero dependencies).

In production the dense channel is meant to be pgvector/FAISS embeddings
(`LLMProvider.embed`, PRD §10.1) — swap `_TfIdfCosine` for that behind the same
`search()` interface; the fusion and the citation contract stay unchanged.

Every hit carries its `source`, so any context fed to an LLM is always attributable —
the retrieval layer never introduces an un-cited fact.
"""
from __future__ import annotations

import math
import re
from dataclasses import dataclass
from typing import Dict, List, Optional

from .knowledge import FOODS, GUIDELINE_RULES, RECIPES

_WORD = re.compile(r"[a-z0-9]+")
_RRF_K = 60  # standard RRF smoothing constant


def _tok(s: str) -> List[str]:
    return _WORD.findall(s.lower())


@dataclass
class Doc:
    id: str
    kind: str          # 'rule' | 'recipe'
    text: str          # indexing text — includes topic/tags/ingredients for search recall
    source: str
    meta: dict
    display: str = ""  # human-facing text (no raw ids) for citation cards / search UI


def _build_corpus() -> List[Doc]:
    docs: List[Doc] = []
    for g in GUIDELINE_RULES:
        docs.append(Doc(f"rule:{g['topic']}", "rule",
                        f"{g['topic']} {g['statement']}",
                        f"{g['source']} p.{g.get('page', '')}".strip(" p."),
                        {"value": g.get("value")},
                        display=g["statement"]))
    for r in RECIPES.values():
        ings = " ".join(FOODS[i.food_id].name for i in r.ingredients if i.food_id in FOODS)
        text = f"{r.name} {r.role.value} {r.region.value if r.region else ''} {' '.join(r.tags)} {ings}"
        docs.append(Doc(f"recipe:{r.id}", "recipe", text, "recipe DB",
                        {"recipe_id": r.id}, display=r.name))
    return docs


class _BM25:
    """Sparse channel: Okapi BM25 over document tokens."""
    def __init__(self, docs: List[Doc], k1: float = 1.5, b: float = 0.75):
        self.docs = docs
        self.k1, self.b = k1, b
        self.toks = [_tok(d.text) for d in docs]
        self.dl = [len(t) for t in self.toks]
        self.avgdl = (sum(self.dl) / len(docs)) if docs else 0.0
        self.df: Dict[str, int] = {}
        for t in self.toks:
            for w in set(t):
                self.df[w] = self.df.get(w, 0) + 1
        self.N = len(docs)

    def _idf(self, w: str) -> float:
        n = self.df.get(w, 0)
        return math.log(1 + (self.N - n + 0.5) / (n + 0.5))

    def score(self, query: str) -> Dict[int, float]:
        q = _tok(query)
        out: Dict[int, float] = {}
        for i in range(len(self.docs)):
            tf: Dict[str, int] = {}
            for w in self.toks[i]:
                tf[w] = tf.get(w, 0) + 1
            s = 0.0
            for w in q:
                f = tf.get(w, 0)
                if not f:
                    continue
                dl = self.dl[i] or 1
                s += self._idf(w) * f * (self.k1 + 1) / (f + self.k1 * (1 - self.b + self.b * dl / (self.avgdl or 1)))
            if s > 0:
                out[i] = s
        return out


class _TfIdfCosine:
    """Dense channel (dependency-free): L2-normalised TF-IDF vectors + cosine.

    Stands in for embedding search until pgvector/FAISS is wired in (PRD §12.3);
    it catches wording overlap that exact-keyword BM25 under-weights.
    """
    def __init__(self, docs: List[Doc]):
        self.docs = docs
        self.toks = [_tok(d.text) for d in docs]
        self.df: Dict[str, int] = {}
        for t in self.toks:
            for w in set(t):
                self.df[w] = self.df.get(w, 0) + 1
        self.N = len(docs)
        self.vecs = [self._vectorize(t) for t in self.toks]

    def _idf(self, w: str) -> float:
        return math.log((1 + self.N) / (1 + self.df.get(w, 0))) + 1.0

    def _vectorize(self, toks: List[str]) -> Dict[str, float]:
        tf: Dict[str, int] = {}
        for w in toks:
            tf[w] = tf.get(w, 0) + 1
        v = {w: (f / (len(toks) or 1)) * self._idf(w) for w, f in tf.items()}
        norm = math.sqrt(sum(x * x for x in v.values())) or 1.0
        return {w: x / norm for w, x in v.items()}

    def score(self, query: str) -> Dict[int, float]:
        qv = self._vectorize(_tok(query))
        out: Dict[int, float] = {}
        for i, dv in enumerate(self.vecs):
            # cosine of normalised vectors = dot product; iterate over the smaller
            small, big = (qv, dv) if len(qv) <= len(dv) else (dv, qv)
            s = sum(x * big.get(w, 0.0) for w, x in small.items())
            if s > 0:
                out[i] = s
        return out


def _fuse(rankings: List[Dict[int, float]]) -> List[int]:
    """Reciprocal Rank Fusion over per-channel {doc_index: score} maps."""
    rrf: Dict[int, float] = {}
    for scores in rankings:
        ordered = sorted(scores.items(), key=lambda kv: -kv[1])
        for rank, (i, _) in enumerate(ordered):
            rrf[i] = rrf.get(i, 0.0) + 1.0 / (_RRF_K + rank + 1)
    return [i for i, _ in sorted(rrf.items(), key=lambda kv: -kv[1])]


class _HybridIndex:
    def __init__(self, docs: List[Doc]):
        self.docs = docs
        self.sparse = _BM25(docs)
        self.dense = _TfIdfCosine(docs)

    def search(self, query: str, kind: Optional[str] = None, top: int = 5) -> List[Doc]:
        fused = _fuse([self.sparse.score(query), self.dense.score(query)])
        out = []
        for i in fused:
            d = self.docs[i]
            if kind and d.kind != kind:
                continue
            out.append(d)
            if len(out) >= top:
                break
        return out


_INDEX = _HybridIndex(_build_corpus())


def retrieve(query: str, kind: Optional[str] = None, top: int = 5) -> List[Doc]:
    """Top cited docs for a query (hybrid BM25 + TF-IDF, RRF-fused).

    kind = 'rule' | 'recipe' | None (both). Every returned Doc carries `source`.
    """
    return _INDEX.search(query, kind=kind, top=top)


def rules_for(query: str, top: int = 3) -> List[Doc]:
    """Shortcut: the top cited guideline rules for a topic — the grounded context
    the pipeline feeds its explanation step (PRD §9.7)."""
    return retrieve(query, kind="rule", top=top)
