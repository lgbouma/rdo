#!/bin/sh
# Runs the core tests with the Command Line Tools' Swift Testing framework
# (no Xcode needed). With Xcode installed, plain `swift test` also works.
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
exec swift test -Xswiftc -F$FW -Xlinker -F$FW -Xlinker -rpath -Xlinker $FW -Xlinker -rpath -Xlinker $LIB "$@"
