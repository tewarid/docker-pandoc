
# Pandoc Dockerfile

[![Docker Cloud Build Status](https://img.shields.io/docker/cloud/build/tewarid/pandoc)](https://hub.docker.com/r/tewarid/pandoc/) [![](https://images.microbadger.com/badges/image/tewarid/pandoc.svg)](https://microbadger.com/images/tewarid/pandoc "Get your own image badge on microbadger.com")

Creates a Docker image with Pandoc, TeX packages to run the [eisvogel](https://github.com/Wandmalfarbe/pandoc-latex-template/) template, Node.js, and [mermaid-filter](https://github.com/raghur/mermaid-filter).

## Pull image from Docker

To fetch the latest automated build image from Docker Hub

```bash
docker pull tewarid/pandoc
```

This pulls the latest tag built from main branch and may not always be stable, hence it is recommended you pull a stable tag

```bash
docker pull tewarid/pandoc:latest
```

Stable versions are tagged manually from latest and pushed to Docker Hub

```bash
docker tag tewarid/pandoc:latest tewarid/pandoc:1.0
docker push tewarid/pandoc:1.0
```

## Build Docker image

To build a new image

```bash
docker build -t tewarid/pandoc:latest .
```

## Run Pandoc

Assuming you have a bash script `run-pandoc.sh` on the host such as

```bash
#!/bin/sh
pandoc title.md doc.md -f markdown -o doc.pdf --toc -F mermaid-filter --template ./eisvogel.tex --variable titlepage=true --variable caption-justification=centering
```

Here's how you can invoke it in a Docker container

```bash
docker run -v `pwd`:/workdir -w /workdir -i -t --name pandoc-container --entrypoint "/workdir/run-pandoc.sh" tewarid/pandoc:1.0
```

On Windows, an equivalent PowerShell command may look like

```powershell
docker run -i -t -v ${PWD}:/workdir -w /workdir --name pandoc-container --entrypoint "/bin/sh ./run-pandoc.sh" tewarid/pandoc:1.0
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

1. You will get an error message such as the following with mermaid-filter

    ```text
    events.js:292
        throw er; // Unhandled 'error' event
        ^

    Error: ENOENT: no such file or directory, open '/tmp/tmp-11UOaQJNu37LGm.tmp.png'
    Emitted 'error' event on ReadStream instance at:
        at internal/fs/streams.js:136:12
        at FSReqCallback.oncomplete (fs.js:156:23) {
    errno: -2,
    code: 'ENOENT',
    syscall: 'open',
    path: '/tmp/tmp-11UOaQJNu37LGm.tmp.png'
    }
    Error running filter mermaid-filter:
    Filter returned error status 1
    ```

    To fix it, create a file called `.puppeteer.json` in the directory you run pandoc, that contains

    ```json
    {
        "executablePath": "/usr/bin/chromium-browser",
        "args": ["--no-sandbox"]
    }
    ```
