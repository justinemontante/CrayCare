"""CrayCare ML module — Water Quality Classification (WQC) for crayfish aquaculture.

Uses an XGBoost classifier to predict water quality level (Low / Moderate / High / Critical)
from rolling sensor features. See features.py for the full feature-engineering pipeline
and agency_standards.py for DENR/DA-BFAR/FAO threshold rationale.
"""
