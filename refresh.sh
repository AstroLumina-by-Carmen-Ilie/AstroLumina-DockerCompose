#!/bin/bash

repos=(
  "AstroLumina-AstrologyAPI"
  "AstroLumina-BookingAPI"
  "AstroLumina-PaymentAPI"
  "AstroLumina-Frontend"
)
for repo in "${repos[@]}"; do
  echo "Refreshing $repo..."
  cd "/home/daniel/Workdir/AstroLumina/$repo"
  doppler run -- docker compose down
  cd ..
done