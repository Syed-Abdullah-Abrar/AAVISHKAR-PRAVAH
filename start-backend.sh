#!/bin/bash
cd /home/syed/dev/AAVISHKAR-PRAVAH/apps/o2_backend
export PYTHONPATH=/home/syed/dev/AAVISHKAR-PRAVAH
uvicorn main:app --reload --port 8000 --host 0.0.0.0
