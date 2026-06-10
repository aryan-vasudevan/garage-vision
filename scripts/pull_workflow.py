#!/usr/bin/env python3
"""
Regenerate the embedded workflow the app runs (garage-vision/workflow.json).

The live Roboflow workflow `custom-workflow-5` is built for *video* (ByteTrack +
time_in_zone) and does not work on single still frames, which is what the app
sends. This script pulls just the piece you tune visually in Roboflow — the
driveway zone polygon (the `drawn_points` in the Scale_Zone block) — and rebuilds
a corrected, fully STATELESS spec around it:

  * scales the zone from the real image size (the live block has a numpy-type bug
    that makes it fall back to 2160x3840),
  * filters vehicles whose bottom-center is in the zone with no tracker,
  * crops the plate straight from the vehicle crop (avoids the rollup block, which
    errors without `root_parent_dimensions`).

Usage:
    export ROBOFLOW_API_KEY=...        # app.roboflow.com/settings/api
    python3 scripts/pull_workflow.py

So to re-tune the driveway zone: redraw it in the Roboflow editor, save, then run
this script.
"""
import ast
import json
import os
import re
import sys
import urllib.request
import pathlib

WORKSPACE = "dev-m9yee"
WORKFLOW = "custom-workflow-5"
DEST = pathlib.Path(__file__).resolve().parent.parent / "garage-vision" / "workflow.json"

api_key = os.environ.get("ROBOFLOW_API_KEY", "").strip()
if not api_key:
    sys.exit("ROBOFLOW_API_KEY is not set.")

url = f"https://api.roboflow.com/{WORKSPACE}/workflows/{WORKFLOW}?api_key={api_key}"
with urllib.request.urlopen(url, timeout=30) as resp:
    config = json.loads(json.load(resp)["workflow"]["config"])["specification"]

# Extract the zone polygon (and its reference frame) from the live Scale_Zone block.
scale_code = next(
    b["code"]["run_function_code"]
    for b in config["dynamic_blocks_definitions"]
    if b["manifest"]["block_type"] == "Scale_Zone"
)
ref_w = float(re.search(r"reference_width\s*=\s*([\d.]+)", scale_code).group(1))
ref_h = float(re.search(r"reference_height\s*=\s*([\d.]+)", scale_code).group(1))
drawn_points = ast.literal_eval(re.search(r"drawn_points\s*=\s*(\[\[.*?\]\])", scale_code).group(1))

# Image-based zone scaling (reads real frame size, no metadata dependency).
scale_run = f"""def run(self, image):
    h, w = int(image.numpy_image.shape[0]), int(image.numpy_image.shape[1])
    ref_w, ref_h = {ref_w}, {ref_h}
    drawn = {drawn_points}
    return {{'zone': [[int(round(max(0.0, min(1.0, x / ref_w)) * (w - 1))), int(round(max(0.0, min(1.0, y / ref_h)) * (h - 1)))] for x, y in drawn]}}
"""

# Stateless "bottom-center inside polygon" filter.
filter_run = """def run(self, predictions, zone):
    import numpy as np
    poly = np.array(zone, dtype=float)
    def inside(px, py):
        n = len(poly); c = False; j = n - 1
        for i in range(n):
            xi, yi = poly[i]; xj, yj = poly[j]
            if ((yi > py) != (yj > py)) and (px < (xj - xi) * (py - yi) / (yj - yi + 1e-9) + xi):
                c = not c
            j = i
        return c
    mask = np.array([inside((x1 + x2) / 2.0, y2) for (x1, y1, x2, y2) in predictions.xyxy], dtype=bool)
    return {'in_zone': predictions[mask]}
"""

img_in = {"type": "DynamicInputDefinition", "selector_types": ["input_image", "step_output"],
          "selector_data_kind": {"input_image": ["image"], "step_output": ["image"]}}
det_in = {"type": "DynamicInputDefinition", "selector_types": ["step_output"],
          "selector_data_kind": {"step_output": ["object_detection_prediction"]}}
list_in = {"type": "DynamicInputDefinition", "selector_types": ["step_output"],
           "selector_data_kind": {"step_output": ["list_of_values"]}}

spec = {
    "version": "1.0",
    "inputs": [{"type": "WorkflowImage", "name": "image"}],
    "steps": [
        {"type": "roboflow_core/roboflow_object_detection_model@v3", "name": "car_detector",
         "images": "$inputs.image", "model_id": "rfdetr-nano", "confidence_mode": "custom",
         "custom_confidence": 0.5, "class_filter": ["car", "truck"]},
        {"type": "Scale_Zone", "name": "scale_driveway_zone", "image": "$inputs.image"},
        {"type": "Filter_In_Zone", "name": "filter_in_zone",
         "predictions": "$steps.car_detector.predictions", "zone": "$steps.scale_driveway_zone.zone"},
        {"type": "roboflow_core/dynamic_crop@v1", "name": "crop_cars_in_zone",
         "images": "$inputs.image", "predictions": "$steps.filter_in_zone.in_zone"},
        {"type": "roboflow_core/roboflow_object_detection_model@v3", "name": "license_plate_detector",
         "images": "$steps.crop_cars_in_zone.crops", "model_id": "license-plate-recognition-rxg4e/4",
         "confidence_mode": "custom", "custom_confidence": 0.3},
        {"type": "roboflow_core/dynamic_crop@v1", "name": "crop_license_plates",
         "images": "$steps.crop_cars_in_zone.crops", "predictions": "$steps.license_plate_detector.predictions"},
        # No flip step: the live camera sends an un-mirrored frame (forward plate),
        # so OCR reads the crop directly. (VideoReplaySource flips the clip to match.)
        {"type": "roboflow_core/glm_ocr@v1", "name": "license_plate_ocr",
         "images": "$steps.crop_license_plates.crops", "task_type": "text-recognition", "model_version": "glm-ocr"},
        {"type": "roboflow_core/dimension_collapse@v1", "name": "collapse_plate_text",
         "data": "$steps.license_plate_ocr.parsed_output"},
    ],
    "outputs": [
        {"type": "JsonField", "name": "cars_in_zone", "selector": "$steps.filter_in_zone.in_zone"},
        {"type": "JsonField", "name": "license_plates", "selector": "$steps.license_plate_detector.predictions"},
        {"type": "JsonField", "name": "plate_text", "selector": "$steps.collapse_plate_text.output"},
    ],
    "dynamic_blocks_definitions": [
        {"type": "DynamicBlockDefinition",
         "manifest": {"type": "ManifestDescription", "block_type": "Scale_Zone",
                      "description": "Scale the driveway polygon to the real frame size.",
                      "inputs": {"image": img_in},
                      "outputs": {"zone": {"type": "DynamicOutputDefinition", "kind": ["list_of_values"]}}},
         "code": {"type": "PythonCode", "run_function_code": scale_run}},
        {"type": "DynamicBlockDefinition",
         "manifest": {"type": "ManifestDescription", "block_type": "Filter_In_Zone",
                      "description": "Keep detections whose bottom-center is inside the zone.",
                      "inputs": {"predictions": det_in, "zone": list_in},
                      "outputs": {"in_zone": {"type": "DynamicOutputDefinition", "kind": ["object_detection_prediction"]}}},
         "code": {"type": "PythonCode", "run_function_code": filter_run}},
    ],
}

DEST.write_text(json.dumps(spec, indent=2) + "\n")
print(f"Wrote {DEST}")
print(f"  zone reference: {int(ref_w)}x{int(ref_h)}, {len(drawn_points)} points")
print(f"  steps:   {[s['name'] for s in spec['steps']]}")
print(f"  outputs: {[o['name'] for o in spec['outputs']]}")