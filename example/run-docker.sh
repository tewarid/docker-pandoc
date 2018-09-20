#!/bin/bash
docker run --rm -i -t -v `pwd`:/workdir -w /workdir tewarid/pandoc sh run-pandoc.sh
