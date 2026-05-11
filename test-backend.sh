#!/bin/bash
# Start O2 Backend server in background
cd /home/syed/dev/AAVISHKAR-PRAVAH/apps/o2_backend
export PYTHONPATH=/home/syed/dev/AAVISHKAR-PRAVAH
python3 -m uvicorn main:app --port 8000 --host 0.0.0.0 &
echo "Server PID: $!"
sleep 4
curl -s http://localhost:8000/health
echo ""
curl -s http://localhost:8000/ivr/ivr/health
echo ""
curl -s http://localhost:8000/risk/risk/levels | head -c 200
echo ""