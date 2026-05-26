#!/bin/sh
set -e

exec ./api-server -port "${PORT}"
