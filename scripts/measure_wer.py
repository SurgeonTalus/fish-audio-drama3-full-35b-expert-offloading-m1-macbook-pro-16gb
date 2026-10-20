#!/usr/bin/env python3
"""Beregn ordfeilrate (WER) for de genererte lydklippene.

Sammenligner Whisper-transkripsjon mot referenceteksten, og rapporterer
ordfeilrate (WER) for hver modell/språk-kombinasjon.
"""
import re
import sys
import warnings

warnings.filterwarnings("ignore")
import whisper  # noqa: E402

NO_EN = (
    "Mal et A4-ark i grønne og gule nyanser. "
    "Mal en stor sirkel på 25,5 cm og fyll hele sirkelen med farge."
)

EN = (
    "I have achieved a high level of proficiency, demonstrated by details such as: "
    "creating varied imprints using different plants, painting the jewelry pieces, "
    "crafting jewelry in various shapes, and investing time and making multiple attempts. "
    "Exploring texture and small-scale craft projects using clay. "
    "Creating clay slabs featuring nature imprints. "
    "Making small jewelry pieces using seashell imprints and paint. "
    "Variety in imprints, creativity in jewelry design, and effort."
)


def normalize(text):
    """Gjør tekst sammenlignbar: lowercase, strip skilletegn, normaliser mellomrom."""
    text = text.lower().replace("–", "-").replace("—", "-")
    text = re.sub(r"[^a-z0-9æøåæ+\-.,% ]", " ", text)
    text = re.sub(r"([.,])", r" \1 ", text)
    text = re.sub(r"\s+", " ", text)
    return [w for w in text.split() if w not in {".", ","}]


def wer(ref_words, hyp_words):
    """Levenshtein-avstand på ordnivå, delt på referanselengde."""
    if not ref_words:
        return 0.0
    prev = list(range(len(hyp_words) + 1))
    for i, r in enumerate(ref_words, 1):
        cur = [i]
        for j, h in enumerate(hyp_words, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (r != h)))
        prev = cur
    return prev[len(hyp_words)] / len(ref_words)


def show(label, path, ref, lang, model, extra=""):
    if not __import__("os").path.exists(path):
        print(f"{label}: FIL IKKE FUNNET ({path})")
        return None
    res = model.transcribe(path, language=lang)
    hyp = res["text"].strip()
    r = normalize(ref)
    h = normalize(hyp)
    w = wer(r, h)
    print(f"--- {label} ---")
    print(f"  WER        : {w * 100:.1f} %")
    print(f"  ref-ord    : {len(r)}")
    print(f"  hyp-ord    : {len(h)}")
    print(f"  auto-språk : {res.get('language')}")
    print(f"  tekst      : {hyp}")
    if extra:
        print(f"  {extra}")
    print()
    return w


def main():
    base = sys.argv[1] if len(sys.argv) > 1 else "."
    print("Laster Whisper small-modellen ...\n")
    model = whisper.load_model("small")

    results = {}
    results["full_no"] = show(
        "FULL  Q4_K_S  / norsk",
        f"{base}/audio/norwegian.wav",
        NO_EN,
        "no",
        model,
    )
    results["small_no"] = show(
        "SMALL IQ3_XXS / norsk",
        f"{base}/audio/norwegian_unusable.wav",
        NO_EN,
        "no",
        model,
    )
    results["full_en"] = show(
        "FULL  Q4_K_S  / engelsk",
        f"{base}/audio/english_works.wav",
        EN,
        "en",
        model,
    )

    print("=" * 60)
    print("Oppsummering")
    print("=" * 60)
    for k, v in results.items():
        if v is not None:
            print(f"  {k:12s} WER = {v * 100:5.1f} %")


if __name__ == "__main__":
    main()
