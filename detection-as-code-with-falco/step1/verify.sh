#!/bin/bash
# Pass once Falco has produced at least one alert that reached the receiver.
kubectl -n falco logs deploy/falco-webhook-receiver --tail=200 2>/dev/null | grep -q '"rule"'
