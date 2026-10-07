#!/bin/bash

repos=(
  "AstroLumina-AstrologyAPI"
  "AstroLumina-BookingAPI"
  "AstroLumina-PaymentAPI"
  "AstroLumina-Frontend"
)
for repo in "${repos[@]}"; do
  echo "Refreshing $repo..."
  cd "/home/daniel/Workdir/AstroLumina/$repo" || exit 1
  doppler run -- docker compose down --rmi all
  cd ..
done
