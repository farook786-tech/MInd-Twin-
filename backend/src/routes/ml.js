const express = require('express');
const axios = require('axios');
const DatabaseService = require('../database/Database');
const { authMiddleware, canAccessPatient } = require('../middleware/auth');
const TokenBucketMiddleware = require('../middleware/TokenBucketMiddleware');
const router = express.Router();

// AI endpoints proxy to paid external providers; cap usage per authenticated user.
const aiRateLimit = TokenBucketMiddleware({ capacity: 20, windowMs: 60 * 60 * 1000 });

const ML_BASE_URL = process.env.ML_SERVICE_URL || 'http://127.0.0.1:8000';
const ML_TIMEOUT_MS = 1500;

/*
 * Crisis decision layer — DECISION SUPPORT ONLY. Every escalation is routed to
 * a human therapist (crisis_events + therapist alert); nothing here is a
 * diagnosis. Evaluation: docs/ML_SAFETY_EVALUATION.md.
 *
 * Contract (identical in ml_service/crisis_rules.py and the Flutter fallback
 * lib/services/ml_sentiment_service.dart, all generated from
 * ml_service/crisis_lexicon.json):
 *   - hard phrase  -> ALWAYS escalate (never suppressed by idioms or negation)
 *   - soft phrase  -> escalate for review (never suppressed by idioms)
 *   - model >= threshold -> escalate unless a figurative idiom is present
 *   - model unavailable / timeout / malformed -> rule layer still decides
 *     (FAIL SAFE: never escalate:false merely because the model is down)
 */
// BEGIN GENERATED CRISIS LEXICON (source: ml_service/crisis_lexicon.json; do not edit by hand)
const CRISIS_LEXICON = {
  "version": "2026.11.17-4",
  "extra_separators": "\u201c\u201d\u2026\u0964\u0965\u2013\u2014\u00bf\u00a1",
  "model_threshold": 0.35,
  "negation_cues": "(not|never|dont|do not|wont|will not|wouldnt|would not|didnt|isnt|no|im not|i am not)",
  "hard": [
    {
      "id": "kill_myself",
      "cat": "explicit",
      "re": "kill+(s|ing|ed)? ?(my ?self|myslef|myslf|mself|meself|mysef)"
    },
    {
      "id": "end_take_life",
      "cat": "explicit",
      "re": "(end|ending|ended|take|taking|took|takes) (my|my own|own) (life|lives)"
    },
    {
      "id": "end_it_all",
      "cat": "explicit",
      "re": "end(ing)? (it|everything|things|this life|my existence)( all| now| tonight| today| for good| forever)?"
    },
    {
      "id": "suicide_word",
      "cat": "explicit",
      "re": "(suicid|suicde|sucid|sucide|suiside|suisid|suicd)[a-z]*"
    },
    {
      "id": "suicide_hinglish",
      "cat": "hinglish",
      "re": "(khud ?kushi|khud ?khushi|khudkhushi|aatma?hatya|atma?hatya|aatmhatya)[a-z]*"
    },
    {
      "id": "want_to_die",
      "cat": "explicit",
      "re": "(wan+a|wan+t(s|ed|ing)?( to| 2)?|wnt( to)?|ready to|deserve to|deserves to|wish i could|wish to|longing to|like to|decided to|mind to|choose to|chosen to|trying to|try to|need to|plan to|planning to) die+"
    },
    {
      "id": "want_dead",
      "cat": "explicit",
      "re": "(wan+a|want(s|ed|ing)? to|rather|better off|wish i (was|were|could be)|deserve to) (be )?dead"
    },
    {
      "id": "not_want_live",
      "cat": "explicit",
      "re": "(dont|do not|didnt|no longer|never) (really |even |just )?(want|wanna|wish|feel like)( to)? (live|be alive|exist|go on living|keep living|stay alive|be here any ?more|be around any ?more|wake up)"
    },
    {
      "id": "wont_be_here",
      "cat": "explicit",
      "re": "(wont|will not|not going to|not gonna) be (here|around|alive) (tomorrow|any ?more|much longer|for long)"
    },
    {
      "id": "no_reason_live",
      "cat": "explicit",
      "re": "((reason|point|purpose|will) (to |in |of |for )?(me )?(even )?(live|living|being alive|be alive|go on|going on|stay alive|staying alive|existing|being here)|(nothing|no ?one|nobody|nothing left|no reason) to live for)"
    },
    {
      "id": "life_not_worth",
      "cat": "explicit",
      "re": "((life|living) (isnt|is not|aint|is never|not) (even )?worth( living| it)?|not worth living)"
    },
    {
      "id": "stop_existing",
      "cat": "passive",
      "re": "(stop|stopped|cease|ceasing|quit) (to )?(living|existing|exist|to live|being alive)"
    },
    {
      "id": "wish_disappear",
      "cat": "passive",
      "re": "(wish (that )?i (could |would |did |can )?(just |simply )?(not exist|didnt exist|disappear|vanish|fade away|fade out|die|stop existing|cease to exist|sleep forever|never wake up|not wake up|be gone|go away forever|fall asleep forever)|(want|wanna|need) to (just )?(disappear|vanish|fade away|fade out|not exist|stop existing)|(disappear|vanish|run away|go away|leave) and never (come back|return|be found|wake up))"
    },
    {
      "id": "disappear_forever",
      "cat": "passive",
      "re": "(disappear|vanish|go away|be gone|go|leave|sleep) (forever|for good)"
    },
    {
      "id": "wish_hit_me",
      "cat": "passive",
      "re": "((wish|hope|pray)[a-z]* (that )?(a |the |some )?[a-z]+ (would |will |could )?(hit|hits|kill|kills|run over|runs over|end|ends|take|takes) me|favou?r (by|if) (dying|disappearing|leaving|being gone|i (died|disappeared|was gone|left)))"
    },
    {
      "id": "never_wake",
      "cat": "passive",
      "re": "((hope|wish|want|pray)[a-z]* (that )?i (just )?(dont|do not|never|wont|wouldnt|would not|didnt) (ever )?wake up|(sleep|asleep) and (never|not|dont|wont) (ever )?wake up|never wake up again|not wake up tomorrow)"
    },
    {
      "id": "better_off_without_me",
      "cat": "passive",
      "re": "(better|happier|easier|fine|okay|ok|better off|relieved|glad|free)( for [a-z]+)? (without me|if i (was|were|wasnt|werent|was not|were not|didnt|did not|died|disappeared|was dead|was gone|were gone|wasnt here|werent here|wasnt around|was not around|didnt exist|did not exist|never existed))"
    },
    {
      "id": "nobody_would_miss",
      "cat": "passive",
      "re": "(no ?one|nobody|noone|no body) (would|will|is going to|gonna) (even )?(miss|notice|care)"
    },
    {
      "id": "tired_of_living",
      "cat": "passive",
      "re": "(tired|sick|done|exhausted|fed up) (of|with) (living|being alive|life|existing|my life)"
    },
    {
      "id": "give_up_life",
      "cat": "passive",
      "re": "give up on (life|living|my life)"
    },
    {
      "id": "never_born",
      "cat": "passive",
      "re": "wish(ed)? i (had |was |were |wasnt |werent |hadnt )?(never )?(been )?born"
    },
    {
      "id": "dont_deserve_live",
      "cat": "passive",
      "re": "((shouldnt|should not|dont deserve to|do not deserve to|not meant to) (be alive|live|exist)|deserve to die)"
    },
    {
      "id": "death_thoughts",
      "cat": "passive",
      "re": "(think|thinking|thought|thoughts|picturing|imagining|imagine|fantasi[sz]ing|fantasi[sz]e|dreaming|dream)( a lot| constantly| always| often)? (about |of )?(death|dying|being dead|my death|my own death|my funeral|my own funeral|not being here)"
    },
    {
      "id": "death_relief",
      "cat": "passive",
      "re": "(death|dying) (seems|feels|sounds|would be|will be|is) (so )?(peaceful|a relief|like a relief|relief|better|easier|nice|good|the answer|the only way|a mercy|mercy|a blessing|welcome|freedom|an escape)"
    },
    {
      "id": "want_it_to_end",
      "cat": "passive",
      "re": "(want|wanna|wish|need)( it| this| everything| my life| life)?( all)? to (end|be over)( for good| forever| now)?"
    },
    {
      "id": "pain_stop_forever",
      "cat": "passive",
      "re": "(want|need|wish) (the pain|it|this|everything) to (stop|end)( forever| for good)?"
    },
    {
      "id": "over_for_good",
      "cat": "passive",
      "re": "(it|this|everything) (all )?(was|were|to be|is) (all )?over (for good|forever)"
    },
    {
      "id": "cant_keep_living",
      "cat": "passive",
      "re": "(cant|cannot|can not) (keep|go on|continue) living"
    },
    {
      "id": "live_or_die",
      "cat": "passive",
      "re": "((care|matter|mind)[a-z]* (if|whether) i (live|die|died|was dead|wake up)|live or die|mind (dying|being dead)|if i (died|was dead|were dead|didnt wake up|never woke up)|(okay|ok|fine|happy|alright) (with )?(not waking up|never waking up|dying|being dead))"
    },
    {
      "id": "wish_die",
      "cat": "passive",
      "re": "(wish|hope|pray)[a-z]* (that )?i (would |could |will |might )?(die|be dead|get killed|not survive)"
    },
    {
      "id": "goodbye_note",
      "cat": "method_plan",
      "re": "((goodbye|suicide|farewell) (note|letter|message)s?|(letter|letters|note|notes) .{0,40}goodbye|goodbye (everyone|everybody|all|world|forever)|(this is|its) my (goodbye|last message|final message))"
    },
    {
      "id": "self_harm_word",
      "cat": "self_harm",
      "re": "(self ?harm|selfharm|self ?injur|self ?mutilat)[a-z]*"
    },
    {
      "id": "harm_myself",
      "cat": "self_harm",
      "re": "(hurt|hurting|hurts|harm|harming|harmed|punish|punishing|injure|injured|injuring|cut|cutting|cuts|burn|burned|burnt|burning|hit|hitting|scratch|scratched|scratching|starve|starving|starved|poison|poisoning|drown|drowning|hang|hanging|hanged|shoot|shooting|stab|stabbing|choke|choking|off|offed|unalive|unaliving) ?(my ?self|myslef|myslf)"
    },
    {
      "id": "cut_body",
      "cat": "self_harm",
      "re": "(cut|cutting|cuts|slit|slitting|slash|slashing|slice|slicing|burn|burning|burned|burnt|scratch|scratching|scratched) (my |both )?(wrist|wrists|arm|arms|thigh|thighs|leg|legs|vein|veins|skin|body)"
    },
    {
      "id": "cuts_on_me",
      "cat": "self_harm",
      "re": "((fresh|new) (cuts|scars)|cuts on my|cuts i made|covered in (cuts|scars)|(urge|urges) to (cut|hurt|harm|self harm|burn)|(want|wanna|need|going) to (cut|burn|hurt) again|cutting( my ?self)? again|started cutting|until (they|it|i) (bled|bleed)|(bled|bleed|hurt|cut|burn[a-z]*|hit|punch[a-z]*|bruise[a-z]*) .{0,40}on purpose)"
    },
    {
      "id": "blade_on_me",
      "cat": "self_harm",
      "re": "(razor|blade|blades|knife) .{0,40}(my ?self|my (arm|arms|wrist|wrists|thigh|thighs|leg|legs|skin))"
    },
    {
      "id": "head_bang",
      "cat": "self_harm",
      "re": "(bang|banged|banging|hit|hitting|smash|smashed) my head (against|on|into)"
    },
    {
      "id": "overdose",
      "cat": "method_plan",
      "re": "(overdos[a-z]*|od (on|tonight)|oding)"
    },
    {
      "id": "pill_stockpile",
      "cat": "method_plan",
      "re": "((save|saved|saving|stockpil[a-z]*|hoard[a-z]*|collect[a-z]*|stash[a-z]*) (up )?(my |all my |the |these |enough )?(pills|meds|medication|medications|medicine|tablets|sleeping pills)|(pills|meds|tablets|medication) (saved|stockpiled|hidden|stashed))"
    },
    {
      "id": "pill_swallow",
      "cat": "method_plan",
      "re": "((take|taking|took|swallow[a-z]*|down|downed) (all|a bunch|a handful|too many|the whole bottle|all of)( of)? (my |the |these |those )?(pills|meds|medication|tablets)|enough (pills|sleeping pills|meds|tablets) to)"
    },
    {
      "id": "rope_noose",
      "cat": "method_plan",
      "re": "(noose|(bought|buy|buying|got|have|tied|tie|made) (a |the )?rope)"
    },
    {
      "id": "jump_from",
      "cat": "method_plan",
      "re": "((jump|jumping|jumped|throw my ?self|leap|leaping) (off|from|in front of) (a |the |my )?(bridge|building|roof|rooftop|terrace|balcony|cliff|train|tower|window|bus|car|truck|metro)|(on|from) (the|a) (roof|terrace|bridge|balcony|ledge) .{0,30}(jump[a-z]*|end[a-z]*)|step(ping)? in front of (a |the )?(train|bus|car|truck|metro)|drive (my car |the car )?off (the|a) (road|bridge|cliff)|crash[a-z]* my car on purpose|(chosen|chose|picked) (the|a) (bridge|building|method|rope|spot to jump)|(building|bridge|roof|floor|drop|fall|cliff) (is |was )?(tall|high|deep) enough|(tall|high|deep) enough to (die|kill|end|jump))"
    },
    {
      "id": "firearm",
      "cat": "method_plan",
      "re": "((gun|pistol|revolver)( is)? loaded|loaded( the)? (gun|pistol)|(gun|pistol) to my head|(bought|buy|got) a (gun|pistol))"
    },
    {
      "id": "ways_to_die",
      "cat": "method_plan",
      "re": "((ways|way|how|methods?) to (die|kill my ?self|end (my|it)|commit)|(know|figured out|decided|planned|worked out) (exactly )?how (i would|i will|i am going to|im going to|i could|ill|id) do it)"
    },
    {
      "id": "plan_and_date",
      "cat": "method_plan",
      "re": "((plan|date|time) (and|n) (a )?(date|time|method|way)|(plan|planning|planned|plans) (to|on|for) (kill|die|dying|end|hurt|jump|hang|overdose|take my))"
    },
    {
      "id": "give_away_things",
      "cat": "method_plan",
      "re": "giv(e|ing|en) away (all )?(my|all my|of my) (things|stuff|belongings|possessions)"
    },
    {
      "id": "slang",
      "cat": "slang",
      "re": "(kms|kys|k m s|unaliv[a-z]*|un alive|sewer ?slide|self ?delete|commit (die|sudoku|seppuku)|toaster bath)"
    },
    {
      "id": "hi_mar_jaana",
      "cat": "hinglish",
      "re": "mar ja[a-z]*"
    },
    {
      "id": "hi_marna",
      "cat": "hinglish",
      "re": "(marna (hai|chahta|chahti|chahte|he|h)|marne (ka|ki|ko|ke) (mann|man|mn|khayal|khyal|vichar|soch|iccha|ichha|dil|irada))"
    },
    {
      "id": "hi_jeene_mann_nahi",
      "cat": "hinglish",
      "re": "(jeene|jine|jeeni|jeena|jina) (ka|ki|ko|ke) (koi )?(mann|man|mn|iccha|ichha|ichchha|wajah|vajah|matlab|maksad|fayda|faida|dil|reason|point)( bhi)? (nahi|nhi|nai|na|ni)"
    },
    {
      "id": "hi_jeena_nahi",
      "cat": "hinglish",
      "re": "((jeena|jina|jeene) (nahi|nhi|nai|ni) (hai|chahta|chahti|chahte|he|h)|(zinda|jinda) (nahi|nhi|nai) (rehna|rahna|rehnaa)|zinda rehne ka (mann|man) (nahi|nhi)|(nahi|nhi) (rehna|rahna|jeena|jina) (chahta|chahti|chahte|hai)|duniya (mein|me|se) (nahi|nhi) rehna|duniya chhod[a-z]*)"
    },
    {
      "id": "hi_khud_ko",
      "cat": "hinglish",
      "re": "khud ko (khatam|khatm|maar|mar|hurt|nuksan|nuksaan|chot|zakhmi|kaat|kat|jala)[a-z]*"
    },
    {
      "id": "hi_sab_khatam",
      "cat": "hinglish",
      "re": "(sab|sabkuch|sab kuch|zindagi|jindagi|zindgi|life) (khatam|khatm|khtm) (kar|kr)"
    },
    {
      "id": "hi_mere_bina",
      "cat": "hinglish",
      "re": "mere (bina|baad) (sab|sabhi|sabko|ghar wale|family|log)[a-z]* (khush|better|theek|thik|accha|achha|acche|ache|aaram)"
    },
    {
      "id": "hi_zindagi_se_thak",
      "cat": "hinglish",
      "re": "(zindagi|jindagi|zindgi|life|jeene) se (thak|tang|bezaar|bezar)[a-z]*"
    },
    {
      "id": "hi_gayab",
      "cat": "hinglish",
      "re": "gayab ho (ja|jaa)[a-z]*"
    },
    {
      "id": "hi_paida_na",
      "cat": "hinglish",
      "re": "(kaash|kash) (main |mai |me |mein )?(paida|peda) (hi )?(na|nahi|nhi)"
    },
    {
      "id": "hi_na_uthu",
      "cat": "hinglish",
      "re": "(kabhi|phir|fir|wapas|dobara) (na|nahi|nhi) (uth|jaag|jag)[a-z]*"
    },
    {
      "id": "hi_jaan_de",
      "cat": "hinglish",
      "re": "((apni|meri) (jaan|jan) (de|le|dena|lena|dedu|ledu)[a-z]*|(jaan|jan) (dene|lene) (ka|ki|ko|ke))"
    },
    {
      "id": "hi_devanagari",
      "cat": "hinglish",
      "re": "(\u092e\u0930 \u091c\u093e[^ ]*|\u092e\u0930\u0928\u093e[^ ]*|\u092e\u0930\u0928\u0947 [^ ]*|\u091c\u0940\u0928\u0947 \u0915\u093e \u092e\u0928 \u0928\u0939\u0940[^ ]*|\u091c\u0940\u0928\u093e \u0928\u0939\u0940[^ ]*|\u0906\u0924\u094d\u092e\u0939\u0924\u094d\u092f\u093e[^ ]*|\u0916\u0941\u0926\u0915\u0941\u0936\u0940[^ ]*|\u0916\u093c\u0941\u0926\u0915\u0941\u0936\u0940[^ ]*|\u0916\u093c\u0941\u0926\u0915\u0941\u0936\u0940[^ ]*|\u0916\u0941\u0926 \u0915\u094b (\u092e\u093e\u0930|\u0916\u0924\u094d\u092e|\u0916\u093c\u0924\u094d\u092e)[^ ]*)"
    },
    {
      "id": "cant_stay_alive",
      "cat": "explicit",
      "re": "(cant|cannot|can not|dont think i can|not sure i can) (stay|keep|remain) (alive|living|going)"
    },
    {
      "id": "better_off_not_existing",
      "cat": "passive",
      "re": "(better off|rather) (not existing|not alive|not be alive|not being alive|not exist|not live|not be here|not being here|gone|be gone|never born|never existed)"
    },
    {
      "id": "want_feel_pain",
      "cat": "self_harm",
      "re": "((want|need|wanted|needed) to feel (physical )?pain|so i (cut|burn|burned|cutted))"
    },
    {
      "id": "poison_method",
      "cat": "method_plan",
      "re": "(rat poison|pesticide|insecticide|keetnashak|zeh?e?r (kha|pi|pee)[a-z]*|jah?a?r (kha|pi|pee)[a-z]*|sulphas|celphos|drink(ing)? bleach)"
    },
    {
      "id": "count_pills_will",
      "cat": "method_plan",
      "re": "((counted|count|counting) (my |the |all my )?(pills|meds|tablets|medication)|(wrote|write|writing|made|updated) (my |a )?will)"
    },
    {
      "id": "slang_obfuscated",
      "cat": "slang",
      "re": "(wan+a|want to|want 2|wnt to) (d e|d1e|dy|ded|d13)"
    },
    {
      "id": "hi_hamesha",
      "cat": "hinglish",
      "re": "((ja|jaa|so|chala|chali|khatam|gayab)[a-z]* .{0,25}hamesha ke liye|hamesha ke liye (so|ja|chala|chali|khatam|gayab)[a-z]*)"
    },
    {
      "id": "hi_khatam_ho",
      "cat": "hinglish",
      "re": "((main|mai|mujhe|mujko|khud) khatam ho (ja|jaa)[a-z]*|khatam ho (jaana|jana) (hai|chahta|chahti))"
    },
    {
      "id": "waste_of_space",
      "cat": "passive",
      "re": "(waste of (space|oxygen|air|life)|shouldnt exist|should not exist)"
    }
  ],
  "soft": [
    {
      "id": "hopeless",
      "cat": "hopelessness",
      "re": "(hopeless[a-z]*|no hope|(lost|lose|losing) (all )?hope)"
    },
    {
      "id": "pointless",
      "cat": "hopelessness",
      "re": "((nothing|life|everything|it all) (is |feels |seems )?(so )?(pointless|meaningless|hopeless)|nothing matters)"
    },
    {
      "id": "cant_go_on",
      "cat": "hopelessness",
      "re": "(cant|cannot|can not) (do this|take (it|this)|go on|handle (it|this)|cope|keep going)( any ?more| like this)"
    },
    {
      "id": "trapped",
      "cat": "hopelessness",
      "re": "(no way out|no escape|(feel|feeling|am|im) trapped)"
    },
    {
      "id": "burden",
      "cat": "hopelessness",
      "re": "((im|i am|feel like|feel like i am|feel like im) (a |such a |just a )?burden|bojh)"
    },
    {
      "id": "worthless",
      "cat": "hopelessness",
      "re": "worthless"
    },
    {
      "id": "never_better",
      "cat": "hopelessness",
      "re": "((nothing|never) (will |is going to )?(ever )?(get|getting) better|never (going to|gonna) be happy)"
    },
    {
      "id": "nothing_left",
      "cat": "hopelessness",
      "re": "(nothing left|tired of fighting|no ?one cares|nobody cares|nobody loves me|no ?one loves me)"
    },
    {
      "id": "giving_up",
      "cat": "hopelessness",
      "re": "(give up on everything|giving up|want to give up)"
    },
    {
      "id": "drowning",
      "cat": "hopelessness",
      "re": "(im|i am) drowning"
    },
    {
      "id": "just_kill_me",
      "cat": "hopelessness",
      "re": "(just kill me|(i|im|i am) going to die)"
    },
    {
      "id": "hi_hopeless",
      "cat": "hopelessness",
      "re": "((koi )?(umeed|ummeed|umid) (nahi|nhi)|sab (bekaar|bekar)|kuch nahi badlega|kuch theek nahi (hoga|ho raha))"
    }
  ],
  "idiom": [
    {
      "id": "dying_laugh",
      "re": "(dying|die|died|dead) (of |from )?(laugh[a-z]*|laughter)"
    },
    {
      "id": "killing_me",
      "re": "(killing|killed|kills|kill) me( lol| haha)?"
    },
    {
      "id": "kill_for",
      "re": "(would|could) kill for"
    },
    {
      "id": "dead_tired",
      "re": "dead (tired|serious|beat|on|wrong|right)"
    },
    {
      "id": "to_die_for",
      "re": "to die for"
    },
    {
      "id": "killed_it",
      "re": "(killed|killing|kill) (it|that|the [a-z]+)"
    },
    {
      "id": "dying_to",
      "re": "dying to (see|know|try|meet|go|hear|get|watch|eat)"
    },
    {
      "id": "kill_time",
      "re": "kill (some )?time"
    },
    {
      "id": "device_died",
      "re": "(phone|battery|laptop|car|plant|plants) (is |was )?(dead|died|dies)"
    },
    {
      "id": "died_of",
      "re": "(died|die|dying) of (embarrassment|boredom|shame|cringe)"
    },
    {
      "id": "drop_dead",
      "re": "(drop dead|die hard|died down|death of me)"
    },
    {
      "id": "going_to_kill_me",
      "re": "(is|are|gonna|going to) kill me"
    },
    {
      "id": "hi_idiom",
      "re": "((has|hans) (has|hans) ke mar|(bhook|bhukh|garmi|thand) se mar)"
    }
  ]
};
// END GENERATED CRISIS LEXICON

// Env may only make the model MORE sensitive (lower threshold), never less.
const MODEL_THRESHOLD = Math.min(
  CRISIS_LEXICON.model_threshold,
  Number.isFinite(Number(process.env.ML_MODEL_THRESHOLD)) && process.env.ML_MODEL_THRESHOLD !== undefined
    ? Number(process.env.ML_MODEL_THRESHOLD)
    : CRISIS_LEXICON.model_threshold
);

const EXTRA_SEPARATORS = new Set(Array.from(CRISIS_LEXICON.extra_separators));
const wrap = (re) => new RegExp('(?:^| )(?:' + re + ')(?= |$)');
const HARD = CRISIS_LEXICON.hard.map((e) => ({ ...e, rx: wrap(e.re) }));
const SOFT = CRISIS_LEXICON.soft.map((e) => ({ ...e, rx: wrap(e.re) }));
const IDIOM = CRISIS_LEXICON.idiom.map((e) => ({ ...e, rx: wrap(e.re) }));
const NEGATION = wrap(CRISIS_LEXICON.negation_cues);

function normalizeText(text) {
  if (typeof text !== 'string' || text.length === 0) return '';
  const t = text.toLowerCase().replace(/[\u2019\u2018`\u00b4]/g, "'").replace(/'/g, '');
  let out = '';
  for (const ch of t) {
    const code = ch.codePointAt(0);
    const asciiSep = code < 128 && !((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9'));
    out += asciiSep || EXTRA_SEPARATORS.has(ch) ? ' ' : ch;
  }
  return out.split(/\s+/).filter(Boolean).join(' ');
}

function matchRules(text) {
  const n = normalizeText(text);
  const hard = HARD.filter((e) => e.rx.test(n));
  const soft = SOFT.filter((e) => e.rx.test(n));
  const idiom = IDIOM.filter((e) => e.rx.test(n));
  return {
    normalized: n,
    hard: hard.map((e) => e.id),
    hardCategories: [...new Set(hard.map((e) => e.cat))].sort(),
    soft: soft.map((e) => e.id),
    idiom: idiom.map((e) => e.id),
    negationPresent: hard.length > 0 && NEGATION.test(n),
  };
}

/** Parse the model payload; returns null when it is missing or malformed. */
function readModelProbability(modelResult) {
  if (!modelResult || typeof modelResult !== 'object') return null;
  const p = Number(modelResult.probability_crisis);
  if (!Number.isFinite(p) || p < 0 || p > 1) return null;
  return p;
}

/**
 * Pure decision function (exported for tests).
 * @param {string} text
 * @param {number|null} modelProbability null => model unavailable (fail safe)
 */
function evaluateCrisis(text, modelProbability = null) {
  const r = matchRules(text);
  const modelAvailable = typeof modelProbability === 'number' && Number.isFinite(modelProbability);
  const p = modelAvailable ? modelProbability : 0;
  const modelCrisis = modelAvailable && p >= MODEL_THRESHOLD;
  const modelEscalate = modelCrisis && r.idiom.length === 0;

  // A model-only flag below 0.5 is 'review': escalate stays FALSE (no crisis
  // event / alert); review_only marks it for the therapist's non-urgent queue.
  const reviewOnly = r.hard.length === 0 && r.soft.length === 0 && modelEscalate && p < 0.5;
  const escalate = r.hard.length > 0 || r.soft.length > 0 || (modelEscalate && !reviewOnly);
  let severity = 'low';
  let triggerLayer = 'none';
  if (r.hard.length > 0) {
    triggerLayer = 'phrase_hard';
    severity = r.hardCategories.includes('method_plan') || p >= 0.9 ? 'critical' : 'high';
  } else if (r.soft.length > 0) {
    triggerLayer = 'phrase_soft';
    severity = p >= 0.75 ? 'high' : 'moderate';
  } else if (modelEscalate) {
    // Model-only flags below 0.5 go to a lower-urgency 'review' queue (alarm fatigue).
    triggerLayer = 'model';
    severity = p >= 0.75 ? 'high' : p >= 0.5 ? 'moderate' : 'review';
  }

  return {
    escalate,
    severity,
    confidence: p,
    trigger_layer: triggerLayer,
    matched_phrases: [...r.hard, ...r.soft],
    categories: r.hardCategories,
    idiom_suppressed: r.idiom.length > 0 && modelCrisis && r.hard.length === 0 && r.soft.length === 0,
    negation_present: r.negationPresent,
    model_available: modelAvailable,
    review_only: reviewOnly,
    requires_human_review: escalate || reviewOnly,
    lexicon_version: CRISIS_LEXICON.version,
  };
}

/**
 * POST /api/ml/predict
 * Routes a message to the FastAPI crisis model and applies the shared
 * hard/soft phrase + idiom decision. If the ML service is down, times out or
 * returns garbage, the rule layer still decides (available:true,
 * model_available:false) so a crisis phrase is never dropped.
 */
router.post('/predict', authMiddleware, aiRateLimit, async (req, res) => {
  try {
    const { text, patientId } = req.body;

    if (!text || typeof text !== 'string') {
      return res.status(400).json({ success: false, error: 'text is required' });
    }

    // Patients may only run predictions for their own history.
    if (patientId && !canAccessPatient(req, patientId)) {
      return res.status(403).json({ success: false, error: 'Access denied' });
    }

    let modelResult = null;
    try {
      const response = await axios.post(
        `${ML_BASE_URL}/predict`,
        { text },
        { timeout: ML_TIMEOUT_MS }
      );
      modelResult = response.data;
    } catch (error) {
      console.warn('[ML bridge] ML service unavailable, using rule layer only:', error.message);
    }

    const probability = readModelProbability(modelResult);
    const decision = evaluateCrisis(text, probability);

    res.json({
      success: true,
      // A decision is always available: the rule layer runs even without the model.
      available: true,
      model_available: decision.model_available,
      degraded: !decision.model_available,
      model_version: (decision.model_available && modelResult.model_version) || 'unavailable',
      decision,
    });
  } catch (error) {
    console.error('[ML bridge] Error:', error);
    res.status(500).json({ success: false, error: 'ML bridge error' });
  }
});

// Confidence for a stored recommendation based on its evidence level.
function confidenceForEvidence(evidenceLevel) {
  const level = String(evidenceLevel || '').trim().toUpperCase();
  if (level.startsWith('A')) return 0.9;
  if (level.startsWith('B')) return 0.75;
  return 0.6;
}

// Evidence-based default interventions ranked from a patient's latest scores.
function defaultInterventions(wellbeingScore, moodScore) {
  const wellbeing = wellbeingScore ?? 70;
  const mood = moodScore ?? 5;

  const list = [];
  if (wellbeing < 50 || mood < 4) {
    list.push({
      title: 'Crisis safety planning',
      description: 'Co-create a personalized safety plan with emergency contacts and coping strategies.',
      confidence: 0.92,
    });
  }
  list.push({
    title: 'Cognitive behavioral therapy (CBT)',
    description: 'Weekly CBT sessions focused on thought restructuring and behavioral activation.',
    confidence: 0.86,
  });
  list.push({
    title: 'Daily mood & wellbeing journaling',
    description: 'Guided daily check-ins to track mood, sleep, and anxiety trends over time.',
    confidence: 0.78,
  });
  if (wellbeing < 70) {
    list.push({
      title: 'Sleep hygiene coaching',
      description: 'Personalized sleep schedule and relaxation routine to improve rest quality.',
      confidence: 0.72,
    });
  }
  list.push({
    title: 'Peer support group',
    description: 'Weekly moderated support group for shared experiences and social connection.',
    confidence: 0.64,
  });
  return list;
}

/**
 * POST /api/ml/recommend-intervention
 * Returns the top 3 evidence-based interventions for a patient, preferring
 * stored therapist-authored recommendations when they exist.
 */
router.post('/recommend-intervention', authMiddleware, aiRateLimit, async (req, res) => {
  try {
    const { patientId } = req.body;

    if (!patientId) {
      return res.status(400).json({ success: false, error: 'patientId is required' });
    }

    if (!canAccessPatient(req, patientId)) {
      return res.status(403).json({ success: false, error: 'Access denied' });
    }

    const database = DatabaseService.getInstance().getDB();

    // Clients may pass the internal patient id or the Firebase UID.
    const patient = database.prepare(
      'SELECT * FROM patients WHERE id = ? OR user_id = ? LIMIT 1'
    ).get(patientId, patientId);

    const interventions = [];

    if (patient) {
      const stored = database.prepare(
        'SELECT * FROM intervention_recommendations WHERE patient_id = ? ORDER BY created_at DESC'
      ).all(patient.id);

      for (const rec of stored) {
        interventions.push({
          title: rec.recommendation_type,
          description: rec.description,
          confidence: confidenceForEvidence(rec.evidence_level),
          evidence_level: rec.evidence_level,
        });
      }

      if (interventions.length === 0) {
        const latest = database.prepare(
          'SELECT * FROM daily_logs WHERE patient_id = ? ORDER BY created_at DESC LIMIT 1'
        ).get(patient.id);
        const wellbeing = latest?.wellbeing_score ?? patient.wellbeing_score ?? 70;
        const mood = latest?.mood_score ?? 5;
        interventions.push(...defaultInterventions(wellbeing, mood));
      }
    } else {
      interventions.push(...defaultInterventions(70, 5));
    }

    res.json({
      success: true,
      topRecommendations: interventions.slice(0, 3),
    });
  } catch (error) {
    console.error('[ML bridge] recommend-intervention error:', error);
    res.status(500).json({ success: false, error: 'Intervention recommendation failed' });
  }
});

module.exports = router;
module.exports.evaluateCrisis = evaluateCrisis;
module.exports.normalizeText = normalizeText;
module.exports.matchRules = matchRules;
module.exports.readModelProbability = readModelProbability;
module.exports.CRISIS_LEXICON = CRISIS_LEXICON;
module.exports.MODEL_THRESHOLD = MODEL_THRESHOLD;