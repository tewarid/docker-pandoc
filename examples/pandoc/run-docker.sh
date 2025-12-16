#!/bin/bash
docker run --platform linux/amd64 --rm -i -t -v `pwd`:/workdir -w /workdir --entrypoint "./run-pandoc.sh" tewarid/pandoc
