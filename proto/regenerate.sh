#!/bin/bash
# Regenerates Sources/Networking/GTFSRealtime/Generated/GTFSRealtime.pb.swift
# from proto/gtfs-realtime.proto. Only needed if Google updates the GTFS-Realtime
# schema — the generated file is committed, so this isn't a normal build step.
#
# Requires: brew install swift-protobuf (provides protoc-gen-swift; protoc
# itself comes along as a dependency).
set -euo pipefail
cd "$(dirname "$0")"
protoc --swift_out=../Sources/Networking/GTFSRealtime/Generated gtfs-realtime.proto
mv ../Sources/Networking/GTFSRealtime/Generated/gtfs-realtime.pb.swift ../Sources/Networking/GTFSRealtime/Generated/GTFSRealtime.pb.swift
echo "Regenerated GTFSRealtime.pb.swift"
