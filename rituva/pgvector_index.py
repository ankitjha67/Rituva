"""pgvector-backed dense retrieval channel (PRD §12.3).

The in-memory TF-IDF cosine in `retrieval.py` is a dependency-free stand-in for
embedding search. This module is the production path: it stores a fixed-width
embedding per corpus document in a Postgres `vector` column and ranks by cosine
distance (`<=>`) inside the database, so dense retrieval scales past what fits
in process memory and is shared across API workers.

The embedding here is **model-free** — deterministic feature hashing of tokens —
so there is no heavy ML dependency and no network call, and query/document
vectors always land in the same space. A real sentence-embedding model can
replace `embed()` later without touching the pgvector plumbing or the schema
(only the `_DIM` constant).
"""
from __future__ import annotations

import hashlib
import math
import re
from typing import Dict, List

_DIM = 256
_WORD = re.compile(r"[a-z0-9]+")


def _bucket_sign(token: str, dim: int):
    """Stable (cross-process) hash of a token → (bucket, +1/-1). Uses md5, not
    the built-in hash(), which is salted per process and would scatter the same
    word to different buckets in the indexer and the query."""
    h = hashlib.md5(token.encode("utf-8")).digest()
    bucket = int.from_bytes(h[:4], "little") % dim
    sign = 1.0 if (h[4] & 1) else -1.0
    return bucket, sign


def embed(text: str, dim: int = _DIM) -> List[float]:
    """Deterministic, model-free embedding: signed feature hashing with a
    sublinear term weight, L2-normalised so cosine == dot product."""
    vec = [0.0] * dim
    tf: Dict[str, int] = {}
    for tok in _WORD.findall(text.lower()):
        tf[tok] = tf.get(tok, 0) + 1
    for tok, f in tf.items():
        bucket, sign = _bucket_sign(tok, dim)
        vec[bucket] += sign * (1.0 + math.log(f))  # sublinear tf
    norm = math.sqrt(sum(x * x for x in vec)) or 1.0
    return [x / norm for x in vec]


def _literal(vec: List[float]) -> str:
    """pgvector text input form: '[0.1,0.2,...]'."""
    return "[" + ",".join(f"{x:.6g}" for x in vec) + "]"


class PgVectorDense:
    """Dense channel backed by pgvector. Mirrors `retrieval._TfIdfCosine`:
    `score(query)` returns {doc_index: similarity}. Indexes the corpus once
    (idempotently) and ranks inside Postgres.

    `conn` is a long-lived `store._DB` (backend == "pg"). Query failures degrade
    to an empty map, so the hybrid retriever simply falls back to BM25.
    """

    def __init__(self, conn, docs, dim: int = _DIM):
        self.conn = conn
        self.docs = docs
        self.dim = dim
        self._ensure_schema()
        self._index(docs)

    def _ensure_schema(self) -> None:
        cur = self.conn.raw.cursor()
        cur.execute("CREATE EXTENSION IF NOT EXISTS vector")
        cur.execute(
            f"CREATE TABLE IF NOT EXISTS doc_vectors ("
            f"  idx INTEGER PRIMARY KEY, doc_id TEXT, kind TEXT, embedding vector({self.dim}))"
        )
        self.conn.commit()

    def _index(self, docs) -> None:
        cur = self.conn.raw.cursor()
        cur.execute("SELECT count(*) FROM doc_vectors")
        if cur.fetchone()[0] == len(docs):
            return  # already indexed this corpus
        cur.execute("DELETE FROM doc_vectors")
        for i, d in enumerate(docs):
            cur.execute(
                "INSERT INTO doc_vectors (idx, doc_id, kind, embedding) "
                "VALUES (%s, %s, %s, %s::vector)",
                (i, d.id, d.kind, _literal(embed(d.text, self.dim))),
            )
        self.conn.commit()

    def score(self, query: str, top: int = 40) -> Dict[int, float]:
        try:
            cur = self.conn.raw.cursor()
            cur.execute(
                "SELECT idx, 1 - (embedding <=> %s::vector) AS sim "
                "FROM doc_vectors ORDER BY embedding <=> %s::vector LIMIT %s",
                (_literal(embed(query, self.dim)),
                 _literal(embed(query, self.dim)), top),
            )
            return {int(idx): float(sim) for idx, sim in cur.fetchall()}
        except Exception:
            return {}
