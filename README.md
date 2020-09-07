
# Pandoc Dockerfile

[![Docker Build Status](https://img.shields.io/docker/build/tewarid/pandoc.svg)](https://hub.docker.com/r/tewarid/pandoc/) [![](https://images.microbadger.com/badges/image/tewarid/pandoc.svg)](https://microbadger.com/images/tewarid/pandoc "Get your own image badge on microbadger.com")

Creates a Docker image with Pandoc, TeX packages to run the [eisvogel](https://github.com/Wandmalfarbe/pandoc-latex-template/) template, Node.js, and [mermaid-filter](https://github.com/raghur/mermaid-filter).

## Pull image from Docker

To fetch the latest automated build image from Docker Hub

```bash
docker pull tewarid/pandoc
```

## Build Docker image

To build a new image

```bash
docker build -t tewarid/pandoc .
```

## Run Pandoc

Assuming you have a bash script `run-pandoc.sh` on the host such as

```bash
#!/bin/bash
pandoc title.md doc.md -f markdown -o doc.pdf --toc -F mermaid-filter --template ./eisvogel.tex --variable titlepage=true --variable caption-justification=centering
```

Here's how you can invoke it in a Docker container

```bash
docker run -v `pwd`:/workdir -w /workdir -i -t --name pandoc-container --entrypoint "/workdir/run-pandoc.sh" tewarid/pandoc
```

On Windows, an equivalent PowerShell command may look like

```powershell
docker run -i -t -v ${PWD}:/workdir -w /workdir --name pandoc-container --entrypoint "/bin/sh ./run-pandoc.sh" tewarid/pandoc
```

To run the same script again

```bash
docker start -a -i pandoc-container
```

Remove the container when no longer needed

```bash
docker rm pandoc-container
```

## Known Issues

1. You will get the following error message with mermaid-filter

    ```text
    [0202/115116.882391:ERROR:zygote_host_impl_linux.cc(88)] Running as root without --no-sandbox is not supported. See https://crbug.com/638180.
    ```

    To fix it, create a file called `.puppeteer.json` in the directory you run pandoc, that contains

    ```json
    {
    "args": ["--no-sandbox"]
    }
    ```
