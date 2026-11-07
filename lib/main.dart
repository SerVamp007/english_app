import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() => runApp(const WordTenApp());

String norm(String s) =>
    s.trim().toLowerCase().replaceAll('ё', 'е').replaceAll(RegExp(r"[ʻ’'`]"), '');

class Word {
  String en, tr;
  List<String> imgs;
  int box, due;
  Word(this.en, this.tr, this.imgs, {this.box = 0, this.due = 0});
  String? get img => imgs.isEmpty ? null : imgs.first;
  Map<String, dynamic> toJson() =>
      {'en': en, 'tr': tr, 'imgs': imgs, 'box': box, 'due': due};
  factory Word.fromJson(Map<String, dynamic> j) => Word(
      j['en'], j['tr'], List<String>.from(j['imgs']),
      box: j['box'], due: j['due']);
}

class Store {
  late SharedPreferences p;
  List<Word> words = [];
  int coins = 0, streak = 0;
  String lang = 'ru', lastDay = '';

  Future<void> load() async {
    p = await SharedPreferences.getInstance();
    final s = p.getString('words');
    if (s != null) {
      words = (jsonDecode(s) as List)
          .map((e) => Word.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    coins = p.getInt('coins') ?? 0;
    streak = p.getInt('streak') ?? 0;
    lang = p.getString('lang') ?? 'ru';
    lastDay = p.getString('lastDay') ?? '';
  }

  Future<void> save() async {
    await p.setString('words', jsonEncode(words.map((w) => w.toJson()).toList()));
    await p.setInt('coins', coins);
    await p.setInt('streak', streak);
    await p.setString('lang', lang);
    await p.setString('lastDay', lastDay);
  }

  String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';

  void touchDay() {
    final now = DateTime.now();
    final today = _day(now);
    if (lastDay == today) return;
    final y = _day(now.subtract(const Duration(days: 1)));
    streak = lastDay == y ? streak + 1 : 1;
    lastDay = today;
  }

  List<Word> get due {
    final n = DateTime.now().millisecondsSinceEpoch;
    final d = words.where((w) => w.due <= n).toList()
      ..sort((a, b) => a.due.compareTo(b.due));
    return d.take(10).toList();
  }
}

class Api {
  static Future<String?> translate(String w, String lang) async {
    try {
      final u = Uri.parse(
          'https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=$lang&dt=t&q=${Uri.encodeQueryComponent(w)}');
      final r = await http.get(u).timeout(const Duration(seconds: 10));
      final j = jsonDecode(r.body);
      final t = j[0][0][0] as String;
      if (t.trim().isNotEmpty) return t;
    } catch (_) {}
    try {
      final u = Uri.parse(
          'https://api.mymemory.translated.net/get?q=${Uri.encodeQueryComponent(w)}&langpair=en|$lang');
      final r = await http.get(u).timeout(const Duration(seconds: 10));
      final t = jsonDecode(r.body)['responseData']['translatedText'] as String;
      if (t.trim().isNotEmpty) return t;
    } catch (_) {}
    return null;
  }

  static Future<List<String>> images(String w) async {
    try {
      final u = Uri.parse(
          'https://api.openverse.org/v1/images/?q=${Uri.encodeQueryComponent(w)}&page_size=6&mature=false');
      final r = await http
          .get(u, headers: {'User-Agent': 'WordTen/1.0'})
          .timeout(const Duration(seconds: 12));
      final j = jsonDecode(r.body);
      return (j['results'] as List)
          .map((e) => (e['thumbnail'] ?? e['url']) as String?)
          .whereType<String>()
          .where((s) => s.startsWith('http'))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

Widget picFill(String? url) => ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: url == null
          ? const Center(child: Icon(Icons.image_outlined, size: 48))
          : Image.network(url,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) =>
                  const Center(child: Icon(Icons.broken_image_outlined, size: 48)),
              loadingBuilder: (c, child, p) => p == null
                  ? child
                  : const Center(child: CircularProgressIndicator())),
    );

class WordTenApp extends StatelessWidget {
  const WordTenApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'WordTen',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF4F46E5), useMaterial3: true),
        darkTheme: ThemeData(
            colorSchemeSeed: const Color(0xFF4F46E5),
            useMaterial3: true,
            brightness: Brightness.dark),
        home: const Loader(),
      );
}

class Loader extends StatefulWidget {
  const Loader({super.key});
  @override
  State<Loader> createState() => _LoaderState();
}

class _LoaderState extends State<Loader> {
  late final Future<Store> f;
  @override
  void initState() {
    super.initState();
    f = () async {
      final s = Store();
      await s.load();
      return s;
    }();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Store>(
        future: f,
        builder: (c, snap) => snap.hasData
            ? HomePage(store: snap.data!)
            : const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
}

class HomePage extends StatefulWidget {
  final Store store;
  const HomePage({super.key, required this.store});
  @override
  State<HomePage> createState() => _HomeState();
}

class _HomeState extends State<HomePage> {
  Store get s => widget.store;
  final List<TextEditingController> cs =
      List.generate(4, (_) => TextEditingController());
  bool busy = false;

  void toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> open(List<Word> ws, bool review) async {
    final done = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => LessonPage(store: s, words: ws, review: review)));
    if (!mounted) return;
    if (done == true && !review) {
      for (final c in cs) {
        c.clear();
      }
    }
    setState(() {});
  }

  Future<void> start() async {
    final list = cs
        .map((c) => c.text.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    if (list.isEmpty) {
      toast('Впиши хотя бы одно слово');
      return;
    }
    setState(() => busy = true);
    final ws = <Word>[];
    await Future.wait(list.map((t) async {
      final tr = await Api.translate(t, s.lang);
      final im = await Api.images(t);
      if (tr != null) ws.add(Word(t, tr.toLowerCase(), im));
    }));
    if (!mounted) return;
    setState(() => busy = false);
    if (ws.isEmpty) {
      toast('Не получилось найти переводы. Проверь интернет.');
      return;
    }
    ws.sort((a, b) => list.indexOf(a.en).compareTo(list.indexOf(b.en)));
    final pool = ws.length + s.words.where((w) => !list.contains(w.en)).length;
    if (pool < 2) {
      toast('Нужно хотя бы 2 слова. Добавь ещё одно.');
      return;
    }
    await open(ws, false);
  }

  @override
  Widget build(BuildContext context) {
    final due = s.due;
    return Scaffold(
      appBar: AppBar(title: const Text('WordTen'), actions: [
        Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('🪙 ${s.coins}   🔥 ${s.streak}')))
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Выучено слов: ${s.words.length}'),
        if (due.isNotEmpty)
          Card(
              child: ListTile(
            title: Text('Пора повторить: ${due.length}'),
            trailing: FilledButton.tonal(
                onPressed: () => open(due, true), child: const Text('Повторить')),
          )),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'ru', label: Text('Русский')),
            ButtonSegment(value: 'uz', label: Text('Oʻzbekcha')),
          ],
          selected: {s.lang},
          onSelectionChanged: (v) {
            setState(() => s.lang = v.first);
            s.save();
          },
        ),
        const SizedBox(height: 16),
        const Text('Новые слова (до 10 за раз). Впиши только английское слово.',
            style: TextStyle(fontWeight: FontWeight.w600)),
        for (int i = 0; i < cs.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Expanded(
                  child: TextField(
                controller: cs[i],
                autocorrect: false,
                decoration: InputDecoration(
                    border: const OutlineInputBorder(), hintText: 'Word ${i + 1}'),
              )),
              if (cs.length > 2)
                IconButton(
                    onPressed: () => setState(() => cs.removeAt(i)),
                    icon: const Icon(Icons.close)),
            ]),
          ),
        if (cs.length < 10)
          TextButton.icon(
              onPressed: () =>
                  setState(() => cs.add(TextEditingController())),
              icon: const Icon(Icons.add),
              label: const Text('Добавить слово')),
        const SizedBox(height: 8),
        if (busy) const LinearProgressIndicator(),
        FilledButton(
            onPressed: busy ? null : start, child: const Text('Начать урок')),
      ]),
    );
  }
}

enum Stage { intro, write, choose, speak, pic }

const stageNames = {
  Stage.intro: 'Знакомство',
  Stage.write: 'Напиши перевод',
  Stage.choose: 'Выбери перевод',
  Stage.speak: 'Произнеси слово',
  Stage.pic: 'Выбери картинку',
};

class LessonPage extends StatefulWidget {
  final Store store;
  final List<Word> words;
  final bool review;
  const LessonPage(
      {super.key, required this.store, required this.words, required this.review});
  @override
  State<LessonPage> createState() => _LessonState();
}

class _LessonState extends State<LessonPage> {
  late final List<Stage> stages;
  int st = 0, total = 1, earned = 0;
  List<int> queue = [];
  List<Word> opts = [];
  final Set<String> missed = {};
  final ctrl = TextEditingController();
  final tts = FlutterTts();
  final stt = SpeechToText();
  bool answered = false, listening = false, finished = false, speechOk = false;
  bool? ok;
  String msg = '';
  Word? picked;

  Word get cur => widget.words[queue.first];

  @override
  void initState() {
    super.initState();
    stages = widget.review
        ? [Stage.choose, Stage.pic]
        : [Stage.intro, Stage.write, Stage.choose, Stage.speak, Stage.pic];
    tts.setLanguage('en-US');
    startStage();
  }

  @override
  void dispose() {
    ctrl.dispose();
    tts.stop();
    stt.cancel();
    super.dispose();
  }

  void startStage() {
    if (st >= stages.length) {
      finish();
      return;
    }
    var idx = List.generate(widget.words.length, (i) => i);
    if (stages[st] == Stage.pic) {
      idx = idx.where((i) => widget.words[i].imgs.isNotEmpty).toList();
    }
    if (stages[st] != Stage.intro) idx.shuffle();
    if (idx.isEmpty) {
      st++;
      startStage();
      return;
    }
    queue = idx;
    total = idx.length;
    prepare();
  }

  void prepare() {
    answered = false;
    ok = null;
    msg = '';
    picked = null;
    listening = false;
    ctrl.clear();
    final w = cur;
    final stage = stages[st];
    if (stage == Stage.choose || stage == Stage.pic) {
      final pool = [
        ...widget.words,
        ...widget.store.words.where((x) => !widget.words.any((y) => y.en == x.en))
      ].where((x) => x.en != w.en);
      final cand = (stage == Stage.pic
              ? pool.where((x) => x.imgs.isNotEmpty)
              : pool.where((x) => norm(x.tr) != norm(w.tr)))
          .toList()
        ..shuffle();
      opts = [w, ...cand.take(3)]..shuffle();
    }
    if (stage == Stage.intro) tts.speak(w.en);
  }

  void mark(bool good, String m) {
    setState(() {
      answered = true;
      ok = good;
      msg = m;
      if (good) {
        if (!missed.contains(cur.en)) earned += 5;
      } else {
        missed.add(cur.en);
      }
    });
  }

  void advance(bool good) {
    if (!mounted) return;
    setState(() {
      final i = queue.removeAt(0);
      if (!good) queue.add(i);
      if (queue.isEmpty) {
        st++;
        startStage();
      } else {
        prepare();
      }
    });
  }

  Future<void> finish() async {
    final s = widget.store;
    final now = DateTime.now().millisecondsSinceEpoch;
    const days = [1, 3, 7, 14, 30];
    for (final w in widget.words) {
      final bad = missed.contains(w.en);
      if (widget.review) w.box = bad ? 0 : min(w.box + 1, 4);
      w.due = bad ? now + 600000 : now + days[w.box] * 86400000;
      if (!widget.review) {
        s.words.removeWhere((x) => x.en == w.en);
        s.words.add(w);
      }
    }
    earned += 20;
    s.coins += earned;
    s.touchDay();
    await s.save();
    if (mounted) setState(() => finished = true);
  }

  void checkWrite(Word w) {
    if (answered) return;
    final a = norm(ctrl.text);
    final good = norm(w.tr) == a ||
        w.tr.split(RegExp(r'[,;]')).map(norm).contains(a);
    mark(good, good ? 'Верно!' : 'Правильно: ${w.tr}');
  }

  void pick(Word o) {
    if (answered) return;
    final good = o.en == cur.en;
    picked = o;
    mark(good, '');
    Future.delayed(const Duration(milliseconds: 1000), () => advance(good));
  }

  Future<void> listen() async {
    if (!speechOk) {
      speechOk = await stt.initialize(onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && mounted) {
          setState(() => listening = false);
        }
      }, onError: (_) {
        if (mounted) setState(() => listening = false);
      });
    }
    if (!speechOk) {
      setState(() => msg = 'Нет доступа к микрофону. Разреши его в настройках.');
      return;
    }
    final target = norm(cur.en);
    setState(() {
      listening = true;
      msg = 'Слушаю…';
      ok = null;
    });
    await stt.listen(
        localeId: 'en_US',
        onResult: (r) {
          if (answered) return;
          final t = norm(r.recognizedWords);
          if (t.contains(target)) {
            stt.stop();
            mark(true, 'Отлично!');
            Future.delayed(const Duration(milliseconds: 900), () => advance(true));
          } else if (r.finalResult) {
            setState(() {
              listening = false;
              ok = false;
              msg = t.isEmpty ? 'Не расслышал. Попробуй ещё' : 'Услышал: «$t». Попробуй ещё';
            });
          }
        });
  }

  Widget feedback() => SizedBox(
      height: 32,
      child: Text(msg,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: ok == null
                  ? null
                  : (ok! ? Colors.green : Colors.red))));

  @override
  Widget build(BuildContext context) {
    if (finished) {
      return Scaffold(
          appBar: AppBar(title: const Text('Готово!')),
          body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🎉', style: TextStyle(fontSize: 72)),
            Text('+$earned монет 🪙',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text('Ошибок: ${missed.length}'),
            const SizedBox(height: 24),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Дальше')),
          ])));
    }
    final stage = stages[st];
    final w = cur;
    final progress =
        ((st + (total - queue.length).clamp(0, total) / total) / stages.length);
    const big = TextStyle(fontSize: 34, fontWeight: FontWeight.bold);
    Widget body;
    switch (stage) {
      case Stage.intro:
        body = Column(children: [
          GestureDetector(
              onTap: () => setState(() {
                    if (w.imgs.length > 1) w.imgs.add(w.imgs.removeAt(0));
                  }),
              child: SizedBox(width: 220, height: 220, child: picFill(w.img))),
          const Text('Нажми на картинку, чтобы показать другую',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 16),
          Text(w.en, style: big),
          Text(w.tr, style: TextStyle(fontSize: 24, color: Theme.of(context).colorScheme.primary)),
          IconButton(
              onPressed: () => tts.speak(w.en), icon: const Icon(Icons.volume_up, size: 32)),
          const Spacer(),
          SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: () => advance(true), child: const Text('Дальше'))),
        ]);
        break;
      case Stage.write:
        body = Column(children: [
          const SizedBox(height: 24),
          Text(w.en, style: big),
          const SizedBox(height: 16),
          TextField(
              controller: ctrl,
              enabled: !answered,
              autofocus: true,
              autocorrect: false,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), hintText: 'Напиши перевод'),
              onSubmitted: (_) => checkWrite(w)),
          const SizedBox(height: 12),
          feedback(),
          SizedBox(
              width: double.infinity,
              child: FilledButton(
                  onPressed: answered ? () => advance(ok == true) : () => checkWrite(w),
                  child: Text(answered ? 'Дальше' : 'Проверить'))),
        ]);
        break;
      case Stage.choose:
        body = Column(children: [
          const SizedBox(height: 24),
          Text(w.en, style: big),
          IconButton(onPressed: () => tts.speak(w.en), icon: const Icon(Icons.volume_up)),
          const SizedBox(height: 8),
          for (final o in opts)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.tonal(
                        style: FilledButton.styleFrom(
                            backgroundColor: answered && o.en == w.en
                                ? Colors.green
                                : (answered && identical(o, picked) ? Colors.red : null)),
                        onPressed: () => pick(o),
                        child: Text(o.tr, style: const TextStyle(fontSize: 18))))),
        ]);
        break;
      case Stage.speak:
        body = Column(children: [
          SizedBox(width: 180, height: 180, child: picFill(w.img)),
          const SizedBox(height: 12),
          Text(w.en, style: big),
          IconButton(onPressed: () => tts.speak(w.en), icon: const Icon(Icons.volume_up)),
          const Spacer(),
          FloatingActionButton.large(
              onPressed: listening || answered ? null : listen,
              child: Icon(listening ? Icons.mic : Icons.mic_none)),
          const SizedBox(height: 12),
          feedback(),
          TextButton(onPressed: () => advance(true), child: const Text('Пропустить')),
        ]);
        break;
      case Stage.pic:
        body = Column(children: [
          const SizedBox(height: 12),
          Text(w.en, style: big),
          const SizedBox(height: 12),
          Expanded(
              child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: [
                for (final o in opts)
                  GestureDetector(
                      onTap: () => pick(o),
                      child: Container(
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  width: 4,
                                  color: answered && o.en == w.en
                                      ? Colors.green
                                      : (answered && identical(o, picked)
                                          ? Colors.red
                                          : Colors.transparent))),
                          child: picFill(o.img))),
              ])),
        ]);
        break;
    }
    return Scaffold(
      appBar: AppBar(title: Text(stageNames[stage]!)),
      body: SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                LinearProgressIndicator(value: progress.toDouble()),
                const SizedBox(height: 8),
                Expanded(child: body),
              ]))),
    );
  }
}
