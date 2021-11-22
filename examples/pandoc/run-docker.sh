#!/bin/bash
docker run --rm -i -t -v `pwd`:/workdir -w /workdir --entrypoint "./run-pandoc.sh" tewarid/pandoc
