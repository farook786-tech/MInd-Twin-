import os
import pickle

from fastapi import FastAPI
from fastapi.responses import JSONResponse
from pydantic import BaseModel

MODEL_PATH = os.path.join(os.path.dirname(__file__), "crisis_classifier.pkl")
VECTORIZER_PATH = os.path.join(os.path.dirname(__file__), "vectorizer.pkl")
MODEL_VERSION = "v1.0.0"

app = FastAPI(
    title="MindTwin Crisis Detection ML Service",
    description="TF-IDF + Logistic Regression crisis triage model. "
    "Returns raw model output only; escalation decisions are made by the Node bridge.",
    version=MODEL_VERSION,
)

# The model artifacts are trained locally and shipped with the image. If they
# are missing, the service still boots but /predict returns 503 so the Node
# bridge falls back to local phrase detection instead of silently treating
# everything as safe (a false negative would be dangerous in this domain).
model = None
vectorizer = None
if os.path.exists(MODEL_PATH) and os.path.exists(VECTORIZER_PATH):
    with open(MODEL_PATH, "rb") as f:
        model = pickle.load(f)
    with open(VECTORIZER_PATH, "rb") as f:
        vectorizer = pickle.load(f)
    print("Crisis model loaded: crisis_classifier.pkl + vectorizer.pkl")
else:
    print(
        "WARNING: model files missing. /predict will return 503 so the Node "
        "bridge falls back to local detection."
    )


class TextPayload(BaseModel):
    text: str


class PredictResponse(BaseModel):
    crisis_detected: bool
    probability_crisis: float
    model_version: str


@app.get("/health")
def health():
    return {
        "status": "ok" if model is not None else "degraded",
        "model_version": MODEL_VERSION,
        "model_loaded": model is not None,
    }


@app.post("/predict", response_model=PredictResponse)
def predict(payload: TextPayload):
    if model is None or vectorizer is None:
        return JSONResponse(
            status_code=503,
            content={"error": "crisis_model_unavailable", "model_version": MODEL_VERSION},
        )

    text = (payload.text or "").lower().strip()
    if not text:
        return {
            "crisis_detected": False,
            "probability_crisis": 0.0,
            "model_version": MODEL_VERSION,
        }

    features = vectorizer.transform([text])
    proba = model.predict_proba(features)[0]
    # Binary classes are sorted: [safe, crisis] -> proba[1] is the crisis probability.
    probability_crisis = float(proba[1])
    crisis_detected = bool(model.predict(features)[0] == 1)

    return {
        "crisis_detected": crisis_detected,
        "probability_crisis": probability_crisis,
        "model_version": MODEL_VERSION,
    }
