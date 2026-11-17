// Local (offline) sentiment + crisis fallback.
//
// DECISION SUPPORT ONLY: a crisis flag never diagnoses anything; every flag
// is written to crisis_events and routed to a human therapist.
//
// The crisis rules below are GENERATED from ml_service/crisis_lexicon.json
// (the same lexicon the Node bridge backend/src/routes/ml.js and the Python
// service use). Do not edit the generated block by hand; run
//   ml_service/.venv/Scripts/python.exe -I ml_service/tools/sync_crisis_lexicon.py
// test/crisis_detection_eval_test.dart fails if the copies drift.

class SentimentResult {
  final String sentiment;
  final String emotion;
  final double score;
  final double confidence;
  final List<String> clinicalFlags;
  final List<String> crisisKeywords;

  const SentimentResult({
    required this.sentiment,
    required this.emotion,
    required this.score,
    required this.confidence,
    required this.clinicalFlags,
    required this.crisisKeywords,
  });
}

class CrisisDetectionResult {
  final bool crisisDetected;
  final String severity;
  final String triggerLayer;
  final List<String> matchedPhrases;
  final double confidence;
  final String recommendedAction;
  final String safetyPlan;
  final bool negationPresent;

  const CrisisDetectionResult({
    required this.crisisDetected,
    required this.severity,
    required this.triggerLayer,
    required this.matchedPhrases,
    required this.confidence,
    required this.recommendedAction,
    required this.safetyPlan,
    this.negationPresent = false,
  });
}

/// Result of the shared crisis rule contract (mirrors evaluateCrisis in ml.js).
class CrisisRuleDecision {
  final bool escalate;
  final String severity;
  final String triggerLayer;
  final List<String> hardMatches;
  final List<String> softMatches;
  final List<String> hardCategories;
  final List<String> idiomMatches;
  final bool negationPresent;
  final bool modelAvailable;
  final bool reviewOnly;

  const CrisisRuleDecision({
    required this.escalate,
    required this.severity,
    required this.triggerLayer,
    required this.hardMatches,
    required this.softMatches,
    required this.hardCategories,
    required this.idiomMatches,
    required this.negationPresent,
    required this.modelAvailable,
    this.reviewOnly = false,
  });

  List<String> get matchedPhrases => [...hardMatches, ...softMatches];
}

// BEGIN GENERATED CRISIS LEXICON (source: ml_service/crisis_lexicon.json; do not edit by hand)
const String kCrisisLexiconVersion = '2026.11.17-4';
const double kCrisisModelThreshold = 0.35;
const String kCrisisExtraSeparators = '\u{201c}\u{201d}\u{2026}\u{964}\u{965}\u{2013}\u{2014}\u{bf}\u{a1}';
const String kCrisisNegationCues = r'(not|never|dont|do not|wont|will not|wouldnt|would not|didnt|isnt|no|im not|i am not)';
const List<Map<String, String>> kCrisisHardPatterns = [
    {'id': 'kill_myself', 'cat': 'explicit', 're': r'kill+(s|ing|ed)? ?(my ?self|myslef|myslf|mself|meself|mysef)'},
    {'id': 'end_take_life', 'cat': 'explicit', 're': r'(end|ending|ended|take|taking|took|takes) (my|my own|own) (life|lives)'},
    {'id': 'end_it_all', 'cat': 'explicit', 're': r'end(ing)? (it|everything|things|this life|my existence)( all| now| tonight| today| for good| forever)?'},
    {'id': 'suicide_word', 'cat': 'explicit', 're': r'(suicid|suicde|sucid|sucide|suiside|suisid|suicd)[a-z]*'},
    {'id': 'suicide_hinglish', 'cat': 'hinglish', 're': r'(khud ?kushi|khud ?khushi|khudkhushi|aatma?hatya|atma?hatya|aatmhatya)[a-z]*'},
    {'id': 'want_to_die', 'cat': 'explicit', 're': r'(wan+a|wan+t(s|ed|ing)?( to| 2)?|wnt( to)?|ready to|deserve to|deserves to|wish i could|wish to|longing to|like to|decided to|mind to|choose to|chosen to|trying to|try to|need to|plan to|planning to) die+'},
    {'id': 'want_dead', 'cat': 'explicit', 're': r'(wan+a|want(s|ed|ing)? to|rather|better off|wish i (was|were|could be)|deserve to) (be )?dead'},
    {'id': 'not_want_live', 'cat': 'explicit', 're': r'(dont|do not|didnt|no longer|never) (really |even |just )?(want|wanna|wish|feel like)( to)? (live|be alive|exist|go on living|keep living|stay alive|be here any ?more|be around any ?more|wake up)'},
    {'id': 'wont_be_here', 'cat': 'explicit', 're': r'(wont|will not|not going to|not gonna) be (here|around|alive) (tomorrow|any ?more|much longer|for long)'},
    {'id': 'no_reason_live', 'cat': 'explicit', 're': r'((reason|point|purpose|will) (to |in |of |for )?(me )?(even )?(live|living|being alive|be alive|go on|going on|stay alive|staying alive|existing|being here)|(nothing|no ?one|nobody|nothing left|no reason) to live for)'},
    {'id': 'life_not_worth', 'cat': 'explicit', 're': r'((life|living) (isnt|is not|aint|is never|not) (even )?worth( living| it)?|not worth living)'},
    {'id': 'stop_existing', 'cat': 'passive', 're': r'(stop|stopped|cease|ceasing|quit) (to )?(living|existing|exist|to live|being alive)'},
    {'id': 'wish_disappear', 'cat': 'passive', 're': r'(wish (that )?i (could |would |did |can )?(just |simply )?(not exist|didnt exist|disappear|vanish|fade away|fade out|die|stop existing|cease to exist|sleep forever|never wake up|not wake up|be gone|go away forever|fall asleep forever)|(want|wanna|need) to (just )?(disappear|vanish|fade away|fade out|not exist|stop existing)|(disappear|vanish|run away|go away|leave) and never (come back|return|be found|wake up))'},
    {'id': 'disappear_forever', 'cat': 'passive', 're': r'(disappear|vanish|go away|be gone|go|leave|sleep) (forever|for good)'},
    {'id': 'wish_hit_me', 'cat': 'passive', 're': r'((wish|hope|pray)[a-z]* (that )?(a |the |some )?[a-z]+ (would |will |could )?(hit|hits|kill|kills|run over|runs over|end|ends|take|takes) me|favou?r (by|if) (dying|disappearing|leaving|being gone|i (died|disappeared|was gone|left)))'},
    {'id': 'never_wake', 'cat': 'passive', 're': r'((hope|wish|want|pray)[a-z]* (that )?i (just )?(dont|do not|never|wont|wouldnt|would not|didnt) (ever )?wake up|(sleep|asleep) and (never|not|dont|wont) (ever )?wake up|never wake up again|not wake up tomorrow)'},
    {'id': 'better_off_without_me', 'cat': 'passive', 're': r'(better|happier|easier|fine|okay|ok|better off|relieved|glad|free)( for [a-z]+)? (without me|if i (was|were|wasnt|werent|was not|were not|didnt|did not|died|disappeared|was dead|was gone|were gone|wasnt here|werent here|wasnt around|was not around|didnt exist|did not exist|never existed))'},
    {'id': 'nobody_would_miss', 'cat': 'passive', 're': r'(no ?one|nobody|noone|no body) (would|will|is going to|gonna) (even )?(miss|notice|care)'},
    {'id': 'tired_of_living', 'cat': 'passive', 're': r'(tired|sick|done|exhausted|fed up) (of|with) (living|being alive|life|existing|my life)'},
    {'id': 'give_up_life', 'cat': 'passive', 're': r'give up on (life|living|my life)'},
    {'id': 'never_born', 'cat': 'passive', 're': r'wish(ed)? i (had |was |were |wasnt |werent |hadnt )?(never )?(been )?born'},
    {'id': 'dont_deserve_live', 'cat': 'passive', 're': r'((shouldnt|should not|dont deserve to|do not deserve to|not meant to) (be alive|live|exist)|deserve to die)'},
    {'id': 'death_thoughts', 'cat': 'passive', 're': r'(think|thinking|thought|thoughts|picturing|imagining|imagine|fantasi[sz]ing|fantasi[sz]e|dreaming|dream)( a lot| constantly| always| often)? (about |of )?(death|dying|being dead|my death|my own death|my funeral|my own funeral|not being here)'},
    {'id': 'death_relief', 'cat': 'passive', 're': r'(death|dying) (seems|feels|sounds|would be|will be|is) (so )?(peaceful|a relief|like a relief|relief|better|easier|nice|good|the answer|the only way|a mercy|mercy|a blessing|welcome|freedom|an escape)'},
    {'id': 'want_it_to_end', 'cat': 'passive', 're': r'(want|wanna|wish|need)( it| this| everything| my life| life)?( all)? to (end|be over)( for good| forever| now)?'},
    {'id': 'pain_stop_forever', 'cat': 'passive', 're': r'(want|need|wish) (the pain|it|this|everything) to (stop|end)( forever| for good)?'},
    {'id': 'over_for_good', 'cat': 'passive', 're': r'(it|this|everything) (all )?(was|were|to be|is) (all )?over (for good|forever)'},
    {'id': 'cant_keep_living', 'cat': 'passive', 're': r'(cant|cannot|can not) (keep|go on|continue) living'},
    {'id': 'live_or_die', 'cat': 'passive', 're': r'((care|matter|mind)[a-z]* (if|whether) i (live|die|died|was dead|wake up)|live or die|mind (dying|being dead)|if i (died|was dead|were dead|didnt wake up|never woke up)|(okay|ok|fine|happy|alright) (with )?(not waking up|never waking up|dying|being dead))'},
    {'id': 'wish_die', 'cat': 'passive', 're': r'(wish|hope|pray)[a-z]* (that )?i (would |could |will |might )?(die|be dead|get killed|not survive)'},
    {'id': 'goodbye_note', 'cat': 'method_plan', 're': r'((goodbye|suicide|farewell) (note|letter|message)s?|(letter|letters|note|notes) .{0,40}goodbye|goodbye (everyone|everybody|all|world|forever)|(this is|its) my (goodbye|last message|final message))'},
    {'id': 'self_harm_word', 'cat': 'self_harm', 're': r'(self ?harm|selfharm|self ?injur|self ?mutilat)[a-z]*'},
    {'id': 'harm_myself', 'cat': 'self_harm', 're': r'(hurt|hurting|hurts|harm|harming|harmed|punish|punishing|injure|injured|injuring|cut|cutting|cuts|burn|burned|burnt|burning|hit|hitting|scratch|scratched|scratching|starve|starving|starved|poison|poisoning|drown|drowning|hang|hanging|hanged|shoot|shooting|stab|stabbing|choke|choking|off|offed|unalive|unaliving) ?(my ?self|myslef|myslf)'},
    {'id': 'cut_body', 'cat': 'self_harm', 're': r'(cut|cutting|cuts|slit|slitting|slash|slashing|slice|slicing|burn|burning|burned|burnt|scratch|scratching|scratched) (my |both )?(wrist|wrists|arm|arms|thigh|thighs|leg|legs|vein|veins|skin|body)'},
    {'id': 'cuts_on_me', 'cat': 'self_harm', 're': r'((fresh|new) (cuts|scars)|cuts on my|cuts i made|covered in (cuts|scars)|(urge|urges) to (cut|hurt|harm|self harm|burn)|(want|wanna|need|going) to (cut|burn|hurt) again|cutting( my ?self)? again|started cutting|until (they|it|i) (bled|bleed)|(bled|bleed|hurt|cut|burn[a-z]*|hit|punch[a-z]*|bruise[a-z]*) .{0,40}on purpose)'},
    {'id': 'blade_on_me', 'cat': 'self_harm', 're': r'(razor|blade|blades|knife) .{0,40}(my ?self|my (arm|arms|wrist|wrists|thigh|thighs|leg|legs|skin))'},
    {'id': 'head_bang', 'cat': 'self_harm', 're': r'(bang|banged|banging|hit|hitting|smash|smashed) my head (against|on|into)'},
    {'id': 'overdose', 'cat': 'method_plan', 're': r'(overdos[a-z]*|od (on|tonight)|oding)'},
    {'id': 'pill_stockpile', 'cat': 'method_plan', 're': r'((save|saved|saving|stockpil[a-z]*|hoard[a-z]*|collect[a-z]*|stash[a-z]*) (up )?(my |all my |the |these |enough )?(pills|meds|medication|medications|medicine|tablets|sleeping pills)|(pills|meds|tablets|medication) (saved|stockpiled|hidden|stashed))'},
    {'id': 'pill_swallow', 'cat': 'method_plan', 're': r'((take|taking|took|swallow[a-z]*|down|downed) (all|a bunch|a handful|too many|the whole bottle|all of)( of)? (my |the |these |those )?(pills|meds|medication|tablets)|enough (pills|sleeping pills|meds|tablets) to)'},
    {'id': 'rope_noose', 'cat': 'method_plan', 're': r'(noose|(bought|buy|buying|got|have|tied|tie|made) (a |the )?rope)'},
    {'id': 'jump_from', 'cat': 'method_plan', 're': r'((jump|jumping|jumped|throw my ?self|leap|leaping) (off|from|in front of) (a |the |my )?(bridge|building|roof|rooftop|terrace|balcony|cliff|train|tower|window|bus|car|truck|metro)|(on|from) (the|a) (roof|terrace|bridge|balcony|ledge) .{0,30}(jump[a-z]*|end[a-z]*)|step(ping)? in front of (a |the )?(train|bus|car|truck|metro)|drive (my car |the car )?off (the|a) (road|bridge|cliff)|crash[a-z]* my car on purpose|(chosen|chose|picked) (the|a) (bridge|building|method|rope|spot to jump)|(building|bridge|roof|floor|drop|fall|cliff) (is |was )?(tall|high|deep) enough|(tall|high|deep) enough to (die|kill|end|jump))'},
    {'id': 'firearm', 'cat': 'method_plan', 're': r'((gun|pistol|revolver)( is)? loaded|loaded( the)? (gun|pistol)|(gun|pistol) to my head|(bought|buy|got) a (gun|pistol))'},
    {'id': 'ways_to_die', 'cat': 'method_plan', 're': r'((ways|way|how|methods?) to (die|kill my ?self|end (my|it)|commit)|(know|figured out|decided|planned|worked out) (exactly )?how (i would|i will|i am going to|im going to|i could|ill|id) do it)'},
    {'id': 'plan_and_date', 'cat': 'method_plan', 're': r'((plan|date|time) (and|n) (a )?(date|time|method|way)|(plan|planning|planned|plans) (to|on|for) (kill|die|dying|end|hurt|jump|hang|overdose|take my))'},
    {'id': 'give_away_things', 'cat': 'method_plan', 're': r'giv(e|ing|en) away (all )?(my|all my|of my) (things|stuff|belongings|possessions)'},
    {'id': 'slang', 'cat': 'slang', 're': r'(kms|kys|k m s|unaliv[a-z]*|un alive|sewer ?slide|self ?delete|commit (die|sudoku|seppuku)|toaster bath)'},
    {'id': 'hi_mar_jaana', 'cat': 'hinglish', 're': r'mar ja[a-z]*'},
    {'id': 'hi_marna', 'cat': 'hinglish', 're': r'(marna (hai|chahta|chahti|chahte|he|h)|marne (ka|ki|ko|ke) (mann|man|mn|khayal|khyal|vichar|soch|iccha|ichha|dil|irada))'},
    {'id': 'hi_jeene_mann_nahi', 'cat': 'hinglish', 're': r'(jeene|jine|jeeni|jeena|jina) (ka|ki|ko|ke) (koi )?(mann|man|mn|iccha|ichha|ichchha|wajah|vajah|matlab|maksad|fayda|faida|dil|reason|point)( bhi)? (nahi|nhi|nai|na|ni)'},
    {'id': 'hi_jeena_nahi', 'cat': 'hinglish', 're': r'((jeena|jina|jeene) (nahi|nhi|nai|ni) (hai|chahta|chahti|chahte|he|h)|(zinda|jinda) (nahi|nhi|nai) (rehna|rahna|rehnaa)|zinda rehne ka (mann|man) (nahi|nhi)|(nahi|nhi) (rehna|rahna|jeena|jina) (chahta|chahti|chahte|hai)|duniya (mein|me|se) (nahi|nhi) rehna|duniya chhod[a-z]*)'},
    {'id': 'hi_khud_ko', 'cat': 'hinglish', 're': r'khud ko (khatam|khatm|maar|mar|hurt|nuksan|nuksaan|chot|zakhmi|kaat|kat|jala)[a-z]*'},
    {'id': 'hi_sab_khatam', 'cat': 'hinglish', 're': r'(sab|sabkuch|sab kuch|zindagi|jindagi|zindgi|life) (khatam|khatm|khtm) (kar|kr)'},
    {'id': 'hi_mere_bina', 'cat': 'hinglish', 're': r'mere (bina|baad) (sab|sabhi|sabko|ghar wale|family|log)[a-z]* (khush|better|theek|thik|accha|achha|acche|ache|aaram)'},
    {'id': 'hi_zindagi_se_thak', 'cat': 'hinglish', 're': r'(zindagi|jindagi|zindgi|life|jeene) se (thak|tang|bezaar|bezar)[a-z]*'},
    {'id': 'hi_gayab', 'cat': 'hinglish', 're': r'gayab ho (ja|jaa)[a-z]*'},
    {'id': 'hi_paida_na', 'cat': 'hinglish', 're': r'(kaash|kash) (main |mai |me |mein )?(paida|peda) (hi )?(na|nahi|nhi)'},
    {'id': 'hi_na_uthu', 'cat': 'hinglish', 're': r'(kabhi|phir|fir|wapas|dobara) (na|nahi|nhi) (uth|jaag|jag)[a-z]*'},
    {'id': 'hi_jaan_de', 'cat': 'hinglish', 're': r'((apni|meri) (jaan|jan) (de|le|dena|lena|dedu|ledu)[a-z]*|(jaan|jan) (dene|lene) (ka|ki|ko|ke))'},
    {'id': 'hi_devanagari', 'cat': 'hinglish', 're': r'(मर जा[^ ]*|मरना[^ ]*|मरने [^ ]*|जीने का मन नही[^ ]*|जीना नही[^ ]*|आत्महत्या[^ ]*|खुदकुशी[^ ]*|ख़ुदकुशी[^ ]*|ख़ुदकुशी[^ ]*|खुद को (मार|खत्म|ख़त्म)[^ ]*)'},
    {'id': 'cant_stay_alive', 'cat': 'explicit', 're': r'(cant|cannot|can not|dont think i can|not sure i can) (stay|keep|remain) (alive|living|going)'},
    {'id': 'better_off_not_existing', 'cat': 'passive', 're': r'(better off|rather) (not existing|not alive|not be alive|not being alive|not exist|not live|not be here|not being here|gone|be gone|never born|never existed)'},
    {'id': 'want_feel_pain', 'cat': 'self_harm', 're': r'((want|need|wanted|needed) to feel (physical )?pain|so i (cut|burn|burned|cutted))'},
    {'id': 'poison_method', 'cat': 'method_plan', 're': r'(rat poison|pesticide|insecticide|keetnashak|zeh?e?r (kha|pi|pee)[a-z]*|jah?a?r (kha|pi|pee)[a-z]*|sulphas|celphos|drink(ing)? bleach)'},
    {'id': 'count_pills_will', 'cat': 'method_plan', 're': r'((counted|count|counting) (my |the |all my )?(pills|meds|tablets|medication)|(wrote|write|writing|made|updated) (my |a )?will)'},
    {'id': 'slang_obfuscated', 'cat': 'slang', 're': r'(wan+a|want to|want 2|wnt to) (d e|d1e|dy|ded|d13)'},
    {'id': 'hi_hamesha', 'cat': 'hinglish', 're': r'((ja|jaa|so|chala|chali|khatam|gayab)[a-z]* .{0,25}hamesha ke liye|hamesha ke liye (so|ja|chala|chali|khatam|gayab)[a-z]*)'},
    {'id': 'hi_khatam_ho', 'cat': 'hinglish', 're': r'((main|mai|mujhe|mujko|khud) khatam ho (ja|jaa)[a-z]*|khatam ho (jaana|jana) (hai|chahta|chahti))'},
    {'id': 'waste_of_space', 'cat': 'passive', 're': r'(waste of (space|oxygen|air|life)|shouldnt exist|should not exist)'},
];
const List<Map<String, String>> kCrisisSoftPatterns = [
    {'id': 'hopeless', 'cat': 'hopelessness', 're': r'(hopeless[a-z]*|no hope|(lost|lose|losing) (all )?hope)'},
    {'id': 'pointless', 'cat': 'hopelessness', 're': r'((nothing|life|everything|it all) (is |feels |seems )?(so )?(pointless|meaningless|hopeless)|nothing matters)'},
    {'id': 'cant_go_on', 'cat': 'hopelessness', 're': r'(cant|cannot|can not) (do this|take (it|this)|go on|handle (it|this)|cope|keep going)( any ?more| like this)'},
    {'id': 'trapped', 'cat': 'hopelessness', 're': r'(no way out|no escape|(feel|feeling|am|im) trapped)'},
    {'id': 'burden', 'cat': 'hopelessness', 're': r'((im|i am|feel like|feel like i am|feel like im) (a |such a |just a )?burden|bojh)'},
    {'id': 'worthless', 'cat': 'hopelessness', 're': r'worthless'},
    {'id': 'never_better', 'cat': 'hopelessness', 're': r'((nothing|never) (will |is going to )?(ever )?(get|getting) better|never (going to|gonna) be happy)'},
    {'id': 'nothing_left', 'cat': 'hopelessness', 're': r'(nothing left|tired of fighting|no ?one cares|nobody cares|nobody loves me|no ?one loves me)'},
    {'id': 'giving_up', 'cat': 'hopelessness', 're': r'(give up on everything|giving up|want to give up)'},
    {'id': 'drowning', 'cat': 'hopelessness', 're': r'(im|i am) drowning'},
    {'id': 'just_kill_me', 'cat': 'hopelessness', 're': r'(just kill me|(i|im|i am) going to die)'},
    {'id': 'hi_hopeless', 'cat': 'hopelessness', 're': r'((koi )?(umeed|ummeed|umid) (nahi|nhi)|sab (bekaar|bekar)|kuch nahi badlega|kuch theek nahi (hoga|ho raha))'},
];
const List<Map<String, String>> kCrisisIdiomPatterns = [
    {'id': 'dying_laugh', 're': r'(dying|die|died|dead) (of |from )?(laugh[a-z]*|laughter)'},
    {'id': 'killing_me', 're': r'(killing|killed|kills|kill) me( lol| haha)?'},
    {'id': 'kill_for', 're': r'(would|could) kill for'},
    {'id': 'dead_tired', 're': r'dead (tired|serious|beat|on|wrong|right)'},
    {'id': 'to_die_for', 're': r'to die for'},
    {'id': 'killed_it', 're': r'(killed|killing|kill) (it|that|the [a-z]+)'},
    {'id': 'dying_to', 're': r'dying to (see|know|try|meet|go|hear|get|watch|eat)'},
    {'id': 'kill_time', 're': r'kill (some )?time'},
    {'id': 'device_died', 're': r'(phone|battery|laptop|car|plant|plants) (is |was )?(dead|died|dies)'},
    {'id': 'died_of', 're': r'(died|die|dying) of (embarrassment|boredom|shame|cringe)'},
    {'id': 'drop_dead', 're': r'(drop dead|die hard|died down|death of me)'},
    {'id': 'going_to_kill_me', 're': r'(is|are|gonna|going to) kill me'},
    {'id': 'hi_idiom', 're': r'((has|hans) (has|hans) ke mar|(bhook|bhukh|garmi|thand) se mar)'},
];
// END GENERATED CRISIS LEXICON

class _CompiledRule {
  final String id;
  final String cat;
  final RegExp rx;
  _CompiledRule(this.id, this.cat, this.rx);
}

RegExp _wrap(String re) => RegExp('(?:^| )(?:$re)(?= |\$)');

final List<_CompiledRule> _hardRules = kCrisisHardPatterns
    .map((e) => _CompiledRule(e['id']!, e['cat']!, _wrap(e['re']!)))
    .toList(growable: false);
final List<_CompiledRule> _softRules = kCrisisSoftPatterns
    .map((e) => _CompiledRule(e['id']!, e['cat']!, _wrap(e['re']!)))
    .toList(growable: false);
final List<_CompiledRule> _idiomRules = kCrisisIdiomPatterns
    .map((e) => _CompiledRule(e['id']!, '', _wrap(e['re']!)))
    .toList(growable: false);
final RegExp _negationRule = _wrap(kCrisisNegationCues);
final Set<int> _extraSeparators = kCrisisExtraSeparators.runes.toSet();

class MlSentimentService {
  /// Same normalization as ml.js / crisis_rules.py.
  static String normalizeForCrisis(String? text) {
    if (text == null || text.isEmpty) return '';
    final t = text
        .toLowerCase()
        .replaceAll(RegExp('[’‘`´]'), "'")
        .replaceAll("'", '');
    final out = StringBuffer();
    for (final r in t.runes) {
      final isAsciiSep = r < 128 &&
          !((r >= 0x61 && r <= 0x7a) || (r >= 0x30 && r <= 0x39));
      if (isAsciiSep || _extraSeparators.contains(r)) {
        out.write(' ');
      } else {
        out.writeCharCode(r);
      }
    }
    return out
        .toString()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .join(' ');
  }

  /// Pure, synchronous crisis decision. [modelProbability] null means the
  /// model is unavailable: the rule layer still decides (fail safe).
  static CrisisRuleDecision evaluateCrisisText(String? text, {double? modelProbability}) {
    final n = normalizeForCrisis(text);
    final hard = _hardRules.where((r) => r.rx.hasMatch(n)).toList();
    final soft = _softRules.where((r) => r.rx.hasMatch(n)).toList();
    final idiom = _idiomRules.where((r) => r.rx.hasMatch(n)).map((r) => r.id).toList();
    final hardCats = hard.map((r) => r.cat).toSet().toList()..sort();

    final modelAvailable = modelProbability != null && modelProbability.isFinite;
    final p = modelAvailable ? modelProbability : 0.0;
    final modelEscalate = modelAvailable && p >= kCrisisModelThreshold && idiom.isEmpty;

    // Model-only flag below 0.5 = 'review': not an escalation (no crisis event).
    final reviewOnly = hard.isEmpty && soft.isEmpty && modelEscalate && p < 0.5;
    final escalate = hard.isNotEmpty || soft.isNotEmpty || (modelEscalate && !reviewOnly);
    var severity = 'low';
    var layer = 'none';
    if (hard.isNotEmpty) {
      layer = 'phrase_hard';
      severity = hardCats.contains('method_plan') || p >= 0.9 ? 'critical' : 'high';
    } else if (soft.isNotEmpty) {
      layer = 'phrase_soft';
      severity = p >= 0.75 ? 'high' : 'moderate';
    } else if (modelEscalate) {
      // Model-only flags below 0.5 go to a lower-urgency 'review' queue.
      layer = 'model';
      severity = p >= 0.75 ? 'high' : p >= 0.5 ? 'moderate' : 'review';
    }

    return CrisisRuleDecision(
      escalate: escalate,
      severity: severity,
      triggerLayer: layer,
      hardMatches: hard.map((r) => r.id).toList(),
      softMatches: soft.map((r) => r.id).toList(),
      hardCategories: hardCats,
      idiomMatches: idiom,
      negationPresent: hard.isNotEmpty && _negationRule.hasMatch(n),
      modelAvailable: modelAvailable,
      reviewOnly: reviewOnly,
    );
  }

  Future<SentimentResult> analyzeSentiment(String text) async {
    final normalized = text.toLowerCase();
    final matches = _matchedTerms(normalized);
    final crisis = evaluateCrisisText(text);

    double score = 0.0;
    if (matches.contains('hope')) score += 0.35;
    if (matches.contains('calm')) score += 0.25;
    if (matches.contains('good')) score += 0.20;
    if (matches.contains('happy')) score += 0.30;
    if (matches.contains('sad')) score -= 0.35;
    if (matches.contains('anxious')) score -= 0.30;
    if (crisis.softMatches.isNotEmpty) score -= 0.45;
    if (crisis.hardMatches.isNotEmpty) score -= 0.75;

    score = score.clamp(-1.0, 1.0);
    final sentiment = score > 0.15
        ? 'positive'
        : score < -0.15
            ? 'negative'
            : 'neutral';

    final emotion = matches.contains('anxious')
        ? 'anxious'
        : matches.contains('sad')
            ? 'sad'
            : matches.contains('angry')
                ? 'angry'
                : matches.contains('hope')
                    ? 'hopeful'
                    : 'neutral';

    final flags = <String>[];
    if (crisis.softMatches.isNotEmpty) flags.add('hopelessness');
    if (crisis.hardMatches.isNotEmpty) flags.add('self_harm_language');
    if (crisis.escalate) flags.add('crisis_review_required');
    if (matches.contains('sleep')) flags.add('sleep_related_distress');
    if (matches.contains('anxious')) flags.add('anxiety_language');

    return SentimentResult(
      sentiment: sentiment,
      emotion: emotion,
      score: score,
      confidence: matches.isEmpty && !crisis.escalate ? 0.55 : 0.75,
      clinicalFlags: flags,
      crisisKeywords: {...matches, ...crisis.matchedPhrases}.toList(),
    );
  }

  /// Offline crisis fallback. Uses ONLY the shared rule layer (no model on
  /// device), so a hard/soft phrase in the current message always escalates,
  /// regardless of negation or idioms. Hard phrases in [recentHistory] also
  /// escalate (severity at least moderate) so a crisis disclosed a few
  /// messages earlier is not lost.
  Future<CrisisDetectionResult> detectCrisis(
    String messageText,
    String patientId,
    List<String> recentHistory,
  ) async {
    final current = evaluateCrisisText(messageText);
    final historyHard = <String>{};
    for (final entry in recentHistory) {
      historyHard.addAll(evaluateCrisisText(entry).hardMatches);
    }

    final crisisDetected = current.escalate || historyHard.isNotEmpty;
    final severity = current.escalate
        ? current.severity
        : historyHard.isNotEmpty
            ? 'moderate'
            : 'low';
    final isUrgent = severity == 'critical' || severity == 'high';
    final matched = {...current.matchedPhrases, ...historyHard}.toList();
    final confidence = current.hardMatches.isNotEmpty
        ? 0.9
        : current.softMatches.isNotEmpty
            ? 0.7
            : historyHard.isNotEmpty
                ? 0.6
                : 0.0;

    return CrisisDetectionResult(
      crisisDetected: crisisDetected,
      severity: severity,
      triggerLayer: current.escalate
          ? current.triggerLayer
          : historyHard.isNotEmpty
              ? 'history'
              : 'none',
      matchedPhrases: matched,
      confidence: confidence,
      negationPresent: current.negationPresent,
      recommendedAction: isUrgent
          ? 'Open safety resources and contact support immediately.'
          : crisisDetected
              ? 'Your care team has been notified. Offer grounding and encourage therapist follow-up.'
              : 'Offer grounding and encourage therapist follow-up.',
      safetyPlan: isUrgent
          ? 'Move to a safe place, call local emergency services, and contact a trusted person.'
          : 'Pause, breathe slowly, and use coping steps before deciding on next action.',
    );
  }

  /// Non-crisis sentiment vocabulary. Negation handling here is ONLY for
  /// mood words ("not happy"); crisis phrases never use negation suppression.
  List<String> _matchedTerms(String text) {
    final terms = <String>[];

    void addIfMatches(String token, List<String> patterns) {
      for (final pattern in patterns) {
        final index = text.indexOf(pattern);
        if (index < 0) continue;
        final before = text.substring(0, index);
        final preceding = before
            .trim()
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();
        final lastWords = preceding.length > 3
            ? preceding.sublist(preceding.length - 3).join(' ')
            : preceding.join(' ');
        final negated = RegExp(
              r"\b(not|never|n[o']t|don'?t|do not|can'?t|cannot|won'?t|isn'?t|aren'?t|no)\b",
              caseSensitive: false,
            )
            .hasMatch(lastWords);
        if (!negated) {
          terms.add(token);
        }
        break;
      }
    }

    addIfMatches('hope', ['hopeful', 'i have hope', 'better soon', 'improving']);
    addIfMatches('calm', ['calm', 'grounded', 'relaxed']);
    addIfMatches('good', ['good', 'okay', 'fine', 'better']);
    addIfMatches('happy', ['happy', 'glad', 'grateful']);
    addIfMatches('sad', ['sad', 'down', 'cry', 'depressed']);
    addIfMatches('anxious', ['anxious', 'panic', 'worried', 'nervous']);
    addIfMatches('angry', ['angry', 'furious', 'mad', 'frustrated']);
    addIfMatches('sleep', ['sleep', 'insomnia', 'nightmare', 'barely slept']);

    return terms.toSet().toList();
  }
}
