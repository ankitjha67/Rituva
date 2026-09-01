import 'kb.dart';
import 'planner.dart' show dietLabels, dishFormat;

/// On-device port of `rituva/cooking.py` — cooking methods generated from the dish's own
/// Knowledge-DB ingredients, and links to renowned chefs' videos.
///
/// Same two honesty rules as the server: every gram in a step is the DB's own quantity,
/// and spices/aromatics are "to taste" because the DB doesn't carry their amounts. Video
/// links are YouTube *search* endpoints, never a guessed video id.

class Chef {
  final String name, channel, handle, lang;
  final Set<String> tags;
  const Chef(this.name, this.channel, this.handle, this.lang, this.tags);
}

/// Handles verified by HTTP-fetching youtube.com/@<handle> (200 + matching title).
/// Guesses that 404'd were dropped rather than shipped.
const kChefs = <Chef>[
  Chef('Sanjeev Kapoor', 'Sanjeev Kapoor Khazana', 'SanjeevKapoorKhazana', 'Hindi/English',
      {'all', 'north', 'west', 'classic'}),
  Chef('Tarla Dalal', 'Tarla Dalal', 'TarlaDalalsKitchen', 'English',
      {'all', 'veg', 'west', 'gujarati', 'healthy'}),
  Chef('Nisha Madhulika', 'NishaMadhulika', 'NishaMadhulika', 'Hindi',
      {'all', 'veg', 'north', 'jain', 'homestyle'}),
  Chef('Chatori Rajni', 'Chatori rajni', 'ChatoriRajni', 'Hindi',
      {'snack', 'street', 'chaat', 'north'}),
  Chef('Ranveer Brar', 'Chef Ranveer Brar', 'RanveerBrar', 'Hindi/English',
      {'all', 'north', 'restaurant', 'nonveg'}),
  Chef('Kunal Kapur', 'Kunal Kapur', 'KunalKapur', 'Hindi/English',
      {'all', 'north', 'technique', 'nonveg'}),
  Chef("Hebbar's Kitchen", 'Hebbars Kitchen', 'HebbarsKitchen', 'English/Hindi',
      {'all', 'veg', 'south', 'breakfast'}),
  Chef('Home Cooking Show', 'HomeCookingShow', 'HomeCookingShow', 'English/Tamil',
      {'south', 'veg', 'homestyle'}),
  Chef('Sanjyot Keer', 'Your Food Lab', 'YourFoodLab', 'Hindi/English',
      {'all', 'modern', 'west', 'nonveg'}),
  Chef('Bharat Sethi', 'bharatzkitchen', 'bharatzkitchen', 'Hindi',
      {'north', 'nonveg', 'street', 'modern'}),
  Chef('Manjula Jain', "Manjula's Kitchen", 'ManjulasKitchen', 'English (US)',
      {'veg', 'jain', 'abroad', 'homestyle'}),
  Chef('Get Curried', 'Get Curried', 'GetCurried', 'English/Hindi',
      {'all', 'north', 'south', 'nonveg'}),
];

String _dishQuery(Recipe r) {
  final name = r.name.split('(').first.split('+').first.trim();
  return '$name recipe';
}

List<Map<String, dynamic>> videoLinks(KB kb, Recipe r, {int limit = 4}) {
  final labels = dietLabels(kb, r);
  final wants = <String>{};
  if (r.region != null) wants.add(r.region!);
  if (r.role == 'snack') wants.addAll(['snack', 'street']);
  if (r.role == 'breakfast') wants.add('breakfast');
  wants.add(labels.contains('nonveg') ? 'nonveg' : 'veg');
  if (labels.contains('jain')) wants.add('jain');

  final ranked = [...kChefs]..sort((a, b) {
      final oa = a.tags.intersection(wants).length, ob = b.tags.intersection(wants).length;
      if (oa != ob) return ob.compareTo(oa);
      final ga = a.tags.contains('all') ? 1 : 0, gb = b.tags.contains('all') ? 1 : 0;
      if (ga != gb) return gb.compareTo(ga);
      return a.name.compareTo(b.name);
    });

  final q = Uri.encodeQueryComponent(_dishQuery(r));
  final out = <Map<String, dynamic>>[
    for (final c in ranked.take(limit))
      {
        'chef': c.name,
        'channel': c.channel,
        'lang': c.lang,
        'kind': 'search',
        'title': '',
        'url': 'https://www.youtube.com/@${c.handle}/search?query=$q',
      }
  ];
  out.add({
    'chef': 'All chefs',
    'channel': 'YouTube search',
    'lang': '',
    'kind': 'search',
    'title': '',
    'url': 'https://www.youtube.com/results?search_query=$q',
  });
  return out;
}

// -------------------------------------------------------------- method ----
const _vegGroups = {'Vegetables', 'GLV', 'Roots & Tubers', 'Mushrooms'};
const _fleshGroups = {'Meat', 'Fish', 'Poultry', 'Shellfish', 'Flesh', 'Eggs'};

const _templated = {
  'paratha', 'thepla', 'roti', 'puri', 'chilla', 'cheela', 'chila', 'dosa', 'idli',
  'uttapam', 'adai', 'pesarattu', 'dal', 'tadka', 'sambar', 'chana', 'rajma', 'chole',
  'ghugni', 'kadhi', 'curry', 'masala', 'kofta', 'paneer', 'stew', 'rasam', 'sabzi',
  'bhaji', 'poriyal', 'thoran', 'fry', 'bhaja', 'stir-fry', 'bharta', 'roast', 'khichdi',
  'pulao', 'biryani', 'pongal', 'raita', 'salad', 'chaat', 'chutney', 'roasted', 'upma',
  'poha', 'porridge', 'bhurji', 'tikka', 'dhokla', 'soup', 'fruit', 'drink',
};

const _synonyms = {
  'bhel': 'chaat', 'chaas': 'drink', 'lassi': 'drink', 'buttermilk': 'drink',
  'water': 'drink', 'sharbat': 'drink', 'smoothie': 'drink', 'egg': 'bhurji',
  'omelette': 'bhurji', 'mushroom': 'sabzi', 'rice': 'pulao',
};

const _times = {
  'dal': [10, 30], 'tadka': [10, 30], 'sambar': [15, 35], 'rasam': [10, 25],
  'chana': [10, 40], 'rajma': [10, 45], 'chole': [10, 45], 'ghugni': [10, 35],
  'curry': [15, 35], 'masala': [15, 35], 'kofta': [25, 45], 'bharta': [15, 35],
  'paratha': [20, 30], 'thepla': [20, 30], 'roti': [15, 20], 'puri': [20, 30],
  'chilla': [10, 20], 'cheela': [10, 20], 'dosa': [10, 20], 'idli': [10, 25],
  'uttapam': [10, 20], 'adai': [10, 25], 'pesarattu': [10, 20], 'sabzi': [10, 25],
  'bhaji': [10, 25], 'poriyal': [10, 20], 'thoran': [10, 20], 'fry': [10, 20],
  'bhaja': [10, 20], 'stir-fry': [10, 20], 'khichdi': [10, 30], 'pulao': [15, 30],
  'biryani': [30, 60], 'raita': [5, 5], 'salad': [10, 10], 'chaat': [10, 15],
  'chutney': [10, 10], 'roasted': [5, 10], 'roast': [5, 10], 'upma': [10, 20],
  'poha': [10, 20], 'porridge': [5, 15], 'pongal': [10, 30], 'dhokla': [15, 35],
  'bhurji': [10, 15], 'tikka': [20, 30], 'soup': [10, 25], 'kadhi': [15, 30],
  'paneer': [15, 30], 'fruit': [2, 2], 'drink': [5, 5],
};

Map<String, List<List<Object>>> _parts(KB kb, Recipe r) {
  final b = <String, List<List<Object>>>{
    'fat': [], 'pulse': [], 'cereal': [], 'dairy': [], 'veg': [], 'flesh': [],
    'nut': [], 'fruit': [], 'spice': [], 'sugar': [], 'other': [],
  };
  for (final ing in r.ingredients) {
    final f = kb.foods[ing.foodId];
    if (f == null) continue;
    final item = <Object>[f.name, ing.qtyG];
    final g = f.group;
    if (g == 'Fruits') {
      b['fruit']!.add(item);
    } else if (g == 'Oils') {
      b['fat']!.add(item);
    } else if (g == 'Pulses') {
      b['pulse']!.add(item);
    } else if (g == 'Cereals') {
      b['cereal']!.add(item);
    } else if (g == 'Dairy') {
      b['dairy']!.add(item);
    } else if (_vegGroups.contains(g)) {
      b['veg']!.add(item);
    } else if (_fleshGroups.contains(g)) {
      b['flesh']!.add(item);
    } else if (g == 'Nuts') {
      b['nut']!.add(item);
    } else if (g == 'Spices') {
      b['spice']!.add(item);
    } else if (g == 'Sugars') {
      b['sugar']!.add(item);
    } else {
      b['other']!.add(item);
    }
  }
  return b;
}

String _fmtItems(List<List<Object>> items) => items
    .map((e) => '${(e[0] as String).toLowerCase()} ${(e[1] as double).round()} g')
    .join(', ');

String effectiveFormat(KB kb, Recipe r) {
  var f = dishFormat(r);
  if (_templated.contains(f)) return f;
  f = _synonyms[f] ?? f;
  if (_templated.contains(f)) return f;
  final p = _parts(kb, r);
  final has = (String k) => p[k]!.isNotEmpty;
  if (has('fruit') && !has('fat') && !has('cereal') && !has('pulse') && !has('flesh')) {
    return 'fruit';
  }
  if (has('nut') && !has('veg') && !has('cereal') && !has('flesh')) return 'roasted';
  if (r.role == 'veg' && has('veg')) return 'sabzi';
  if (r.role == 'main' && (has('pulse') || has('dairy') || has('flesh'))) return 'curry';
  if (r.role == 'breakfast' && has('cereal')) return 'upma';
  return f;
}

/// Cooking steps for a dish, built from its Knowledge-DB ingredient list.
Map<String, dynamic> method(KB kb, Recipe r) {
  final p = _parts(kb, r);
  final fmt = effectiveFormat(kb, r);
  final steps = <String>[];
  bool has(String k) => p[k]!.isNotEmpty;
  String oil() => has('fat') ? _fmtItems(p['fat']!) : '1 tsp oil';

  if (r.tags.contains('staple') &&
      has('cereal') &&
      !has('veg') &&
      !has('pulse') &&
      !has('flesh') &&
      !['roti', 'paratha', 'puri', 'thepla'].contains(fmt)) {
    steps.add('Rinse ${_fmtItems(p['cereal']!)} in 2–3 changes of water until it runs clear — '
        'this washes off loose surface starch so the grains stay separate.');
    steps.add('Soak 15–20 minutes and drain (optional, but it cooks more evenly).');
    steps.add('Boil in plenty of water until just tender and drain, or cook covered with '
        'about 2 parts water to 1 part grain until every drop is absorbed.');
    steps.add('Rest 5 minutes off the heat, then fluff with a fork and serve.');
  } else if (['paratha', 'thepla', 'roti', 'puri'].contains(fmt)) {
    if (has('cereal')) {
      steps.add('Take ${_fmtItems(p['cereal']!)} in a wide bowl with a pinch of salt.');
    }
    if (has('veg')) {
      steps.add('Grate or finely chop ${_fmtItems(p['veg']!)} and mix it into the flour with '
          'your spices to taste (ajwain, chilli, coriander).');
    } else if (has('pulse')) {
      steps.add('Mix ${_fmtItems(p['pulse']!)} into the flour with spices to taste — this is '
          'the stuffing/binder.');
    }
    steps.add('Add water a little at a time and knead a soft, pliable dough. Rest it 15 '
        'minutes under a damp cloth.');
    steps.add('Divide into equal balls and roll out on a lightly floured board.');
    steps.add('Cook on a hot tawa, turning once, then brush with ${has('fat') ? _fmtItems(p['fat']!) : 'a little oil or ghee'} '
        'and press the edges until golden brown spots appear on both sides.');
    if (has('dairy')) steps.add('Serve hot with ${_fmtItems(p['dairy']!)}.');
  } else if (['chilla', 'cheela', 'chila', 'dosa', 'uttapam', 'adai', 'pesarattu'].contains(fmt)) {
    final base = has('pulse') ? p['pulse']! : p['cereal']!;
    if (base.isNotEmpty) {
      steps.add('Blend ${_fmtItems(base)} with water into a smooth, pourable batter '
          '(soak first if using whole grain or dal).');
    }
    if (['dosa', 'adai', 'uttapam'].contains(fmt)) {
      steps.add('Let the batter ferment 6–8 hours in a warm place until it smells pleasantly '
          'sour and has risen.');
    } else {
      steps.add('Rest the batter 15–20 minutes. Season with salt and spices to taste.');
    }
    final stuffed = ['dosa', 'uttapam'].contains(fmt) && has('veg');
    if (stuffed) {
      steps.add('For the filling, boil and lightly mash ${_fmtItems(p['veg']!)}, then toss it in '
          'a tempering of mustard seeds, curry leaves, onion and turmeric to taste.');
    } else if (has('veg')) {
      steps.add('Finely chop ${_fmtItems(p['veg']!)} and stir through the batter.');
    }
    steps.add('Heat a tawa, pour a ladle of batter and spread it thin. Drizzle '
        '${has('fat') ? _fmtItems(p['fat']!) : 'a few drops of oil'} around the edge.');
    steps.add(stuffed
        ? 'Cook until the base is crisp and golden, spoon the filling along the centre, fold '
            'over and serve hot with chutney and sambar.'
        : 'Cook until the base is golden and lifts cleanly, flip, and cook the other side '
            'briefly. Serve immediately.');
  } else if (['dal', 'tadka', 'sambar', 'chana', 'rajma', 'chole', 'ghugni', 'kadhi',
              'curry', 'masala', 'kofta', 'paneer', 'stew', 'rasam'].contains(fmt)) {
    if (has('pulse')) {
      steps.add('Rinse ${_fmtItems(p['pulse']!)} and soak — 30 minutes for split dal, 6–8 '
          'hours for whole legumes like rajma or chana.');
      steps.add('Pressure-cook with fresh water, a little salt and turmeric until soft '
          '(3–4 whistles for dal, 5–6 for whole legumes).');
    }
    steps.add('For the tadka, heat ${oil()} in a pan. Crackle cumin/mustard seeds, then add '
        'ginger, garlic and green chilli to taste and fry until fragrant.');
    if (has('veg')) {
      steps.add('Add ${_fmtItems(p['veg']!)} and sauté until softened and the raw smell goes.');
    }
    steps.add('Add your ground spices to taste (turmeric, chilli, coriander, garam masala) '
        "and cook 30 seconds so they don't stay raw.");
    if (has('flesh')) {
      steps.add('Add ${_fmtItems(p['flesh']!)}, sear well, then cook through on a low flame.');
    }
    if (has('dairy')) {
      steps.add("Add ${_fmtItems(p['dairy']!)} — if it's paneer, add it late so it stays soft; "
          "if it's curd, whisk and lower the flame so it doesn't split.");
    }
    if (has('pulse')) {
      steps.add('Pour the tadka into the cooked dal (or the dal into the pan), add hot water '
          'to the consistency you like, and simmer 5 minutes so the flavours marry.');
    }
    steps.add('Check salt, finish with coriander and a squeeze of lemon, and serve hot.');
  } else if (['sabzi', 'bhaji', 'poriyal', 'thoran', 'fry', 'bhaja', 'stir-fry', 'bharta',
              'roast'].contains(fmt)) {
    if (has('veg')) {
      steps.add('Wash and cut ${_fmtItems(p['veg']!)} into even pieces so they cook at the '
          'same rate.');
    }
    steps.add('Heat ${oil()}, splutter mustard/cumin seeds, and add curry leaves, garlic or '
        'dried chilli to taste.');
    if (fmt == 'bharta') {
      steps.add('Roast the vegetable directly on the flame until the skin chars and the '
          'inside is soft, then peel and mash it.');
    }
    steps.add('Add the vegetables with a pinch of salt and turmeric. Toss to coat.');
    steps.add('Cover and cook on a low flame, stirring occasionally, until just tender — stop '
        "while there's still a little bite so the nutrients and colour hold.");
    if (['poriyal', 'thoran'].contains(fmt)) {
      steps.add('Finish with grated fresh coconut and toss once more.');
    }
    steps.add('Adjust salt and serve as a side with roti or rice.');
  } else if (['khichdi', 'pulao', 'biryani', 'pongal'].contains(fmt)) {
    if (has('cereal')) {
      steps.add('Rinse ${_fmtItems(p['cereal']!)} until the water runs clear, then soak 20 '
          'minutes and drain.');
    }
    if (has('pulse')) steps.add('Rinse ${_fmtItems(p['pulse']!)} and keep aside.');
    steps.add('Heat ${has('fat') ? _fmtItems(p['fat']!) : '1 tsp ghee or oil'} in a pressure '
        'cooker or heavy pot and temper whole spices (cumin, bay leaf, clove, cinnamon) to taste.');
    if (has('veg')) steps.add('Add ${_fmtItems(p['veg']!)} and sauté 2–3 minutes.');
    if (has('flesh')) {
      steps.add('Add ${_fmtItems(p['flesh']!)} and sear until browned on all sides.');
    }
    steps.add('Add the drained grain and stir 1 minute to coat every grain in fat.');
    steps.add('Add hot water (about 2 parts water to 1 part rice; more for a softer khichdi), '
        'season with salt, and cook until done — 2 whistles, or covered on low till the water '
        'is absorbed.');
    steps.add('Rest 5 minutes off the heat, then fluff gently with a fork and serve.');
  } else if (fmt == 'drink') {
    if (has('dairy')) {
      steps.add('Whisk ${_fmtItems(p['dairy']!)} until completely smooth.');
      steps.add('Add chilled water to the thickness you like — thin for chaas, thicker for lassi.');
    }
    if (has('fruit')) steps.add('Blend in ${_fmtItems(p['fruit']!)}.');
    steps.add('Season to taste — roasted cumin powder, black salt and a few mint or coriander '
        'leaves for chaas; a little sugar or honey for a sweet lassi.');
    steps.add("Serve cold. Don't heat it — the curd will split and the live cultures won't survive.");
  } else if (fmt == 'fruit') {
    if (has('fruit')) {
      steps.add('Wash ${_fmtItems(p['fruit']!)} well under running water.');
      steps.add("Eat whole with the skin on where it's edible — that's where most of the fibre "
          "is — or cut into pieces just before eating so it doesn't oxidise.");
    }
    if (has('nut')) {
      steps.add('Serve alongside ${_fmtItems(p['nut']!)} for a little protein and fat, which '
          'slows the sugar release.');
    }
    if (has('dairy')) steps.add('Optionally top with ${_fmtItems(p['dairy']!)}.');
    steps.add('No cooking needed — best eaten fresh.');
  } else if (['raita', 'salad', 'chaat', 'chutney'].contains(fmt)) {
    if (has('dairy')) {
      steps.add('Whisk ${_fmtItems(p['dairy']!)} until smooth and lump-free.');
    }
    if (has('veg')) steps.add('Finely chop ${_fmtItems(p['veg']!)}.');
    if (has('pulse')) {
      steps.add('Use ${_fmtItems(p['pulse']!)} boiled or sprouted, well drained and cooled.');
    }
    if (has('nut')) steps.add('Roughly crush ${_fmtItems(p['nut']!)}.');
    steps.add('Combine everything and season to taste — roasted cumin powder, black salt, '
        'chilli, lemon juice and fresh coriander.');
    steps.add('Chill briefly and serve fresh; it loses crunch if it sits too long.');
  } else if (fmt == 'roasted') {
    final target = has('nut') ? p['nut']! : (has('pulse') ? p['pulse']! : p['other']!);
    if (target.isNotEmpty) {
      steps.add('Spread ${_fmtItems(target)} in a single layer in a dry, heavy pan.');
    }
    steps.add('Dry-roast on a low-medium flame, stirring constantly, 5–8 minutes until they '
        "colour lightly and smell nutty — they burn fast, so don't walk away.");
    steps.add('Cool completely (they crisp as they cool), season with a little salt or chaat '
        'masala to taste, and store airtight.');
  } else if (['upma', 'poha', 'porridge'].contains(fmt)) {
    if (has('cereal')) {
      steps.add('Prepare ${_fmtItems(p['cereal']!)}: rinse and drain poha, or dry-roast '
          'semolina until it smells nutty.');
    }
    steps.add('Heat ${oil()} and temper mustard seeds, curry leaves and green chilli to taste.');
    if (has('veg')) steps.add('Add ${_fmtItems(p['veg']!)} and sauté until tender.');
    if (has('nut')) steps.add('Add ${_fmtItems(p['nut']!)} and fry until golden.');
    steps.add('Add the grain with salt (and hot water for upma/porridge), stir well, cover and '
        'cook on low 3–5 minutes until fluffy.');
    steps.add('Finish with lemon juice and coriander, and serve warm.');
  } else if (fmt == 'bhurji') {
    steps.add('Heat ${oil()} and fry finely chopped onion, ginger, garlic and green chilli to '
        'taste until soft.');
    if (has('veg')) {
      steps.add('Add ${_fmtItems(p['veg']!)} and cook until the moisture dries off.');
    }
    final main = has('dairy') ? p['dairy']! : (has('flesh') ? p['flesh']! : p['pulse']!);
    if (main.isNotEmpty) {
      steps.add('Crumble in ${_fmtItems(main)} and toss on a high flame for 2–3 minutes — keep '
          "it moving so it stays soft and doesn't rubberise.");
    }
    steps.add('Season with turmeric, chilli and salt to taste, finish with coriander, and serve '
        'hot with roti or pav.');
  } else if (fmt == 'tikka') {
    final main = has('dairy') ? p['dairy']! : (has('flesh') ? p['flesh']! : p['pulse']!);
    if (main.isNotEmpty) steps.add('Cut ${_fmtItems(main)} into even cubes.');
    steps.add('Marinate in thick curd with ginger-garlic paste, chilli, turmeric, garam masala '
        'and salt to taste. Rest at least 30 minutes (overnight is better for meat).');
    if (has('veg')) {
      steps.add('Thread onto skewers alternating with ${_fmtItems(p['veg']!)}.');
    }
    steps.add('Grill, air-fry or pan-sear on high heat, basting with '
        '${has('fat') ? _fmtItems(p['fat']!) : 'a little oil'}, turning until charred at the '
        'edges and cooked through.');
    steps.add('Finish with lemon juice and chaat masala, and serve hot.');
  } else if (fmt == 'dhokla') {
    final base = has('pulse') ? p['pulse']! : p['cereal']!;
    if (base.isNotEmpty) {
      steps.add('Blend ${_fmtItems(base)} into a smooth batter and let it ferment 6–8 hours '
          '(or use fruit salt just before steaming for the quick version).');
    }
    steps.add('Season the batter with salt, sugar, ginger-chilli paste and lemon juice to '
        'taste, then whisk in fruit salt/eno and pour immediately into a greased tin.');
    steps.add('Steam 15–20 minutes until a toothpick comes out clean. Cool slightly and cut '
        'into squares.');
    steps.add('Temper ${oil()} with mustard seeds, sesame, curry leaves and slit green chilli; '
        'pour over the dhokla and garnish with coriander and coconut.');
  } else if (fmt == 'soup') {
    if (has('veg')) steps.add('Roughly chop ${_fmtItems(p['veg']!)}.');
    steps.add('Heat ${oil()}, sweat the aromatics, then add the vegetables and cook 3–4 minutes.');
    if (has('pulse')) {
      steps.add('Add ${_fmtItems(p['pulse']!)} (pre-soaked) for body and protein.');
    }
    steps.add('Add hot water or stock, season, and simmer until everything is tender.');
    steps.add('Blend smooth if you like, adjust seasoning with pepper and lemon, and serve hot.');
  } else {
    if (has('pulse')) {
      steps.add('Rinse and soak ${_fmtItems(p['pulse']!)}, then boil until tender.');
    }
    if (has('cereal')) steps.add('Rinse ${_fmtItems(p['cereal']!)} and cook until soft.');
    steps.add('Heat ${oil()} and temper cumin or mustard seeds with ginger, garlic and chilli '
        'to taste.');
    if (has('veg')) steps.add('Add ${_fmtItems(p['veg']!)} and sauté until tender.');
    if (has('flesh')) steps.add('Add ${_fmtItems(p['flesh']!)} and cook through.');
    if (has('dairy')) {
      steps.add('Stir in ${_fmtItems(p['dairy']!)} towards the end on a low flame.');
    }
    if (has('nut')) steps.add('Add ${_fmtItems(p['nut']!)}.');
    steps.add('Season with salt and your spices to taste, simmer briefly, and serve hot.');
  }

  final t = _times[fmt] ?? const [15, 30];
  return {
    'format': fmt,
    'steps': steps,
    'serves': 1,
    'hands_on_min': t[0],
    'total_min': t[1],
    'time_note': 'typical timing, not measured',
    'source': 'deterministic',
    'intro': '',
    'tips': <String>[],
    'grounding': "Quantities are this dish's Knowledge-DB amounts — the same ones the "
        'nutrition totals are computed from. Spices, salt and aromatics are "to taste": the '
        'DB does not carry their quantities, so Rituva will not invent them.',
  };
}
