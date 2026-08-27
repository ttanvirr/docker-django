# Table of Contents <!-- omit in toc -->

- [1. Overview: Containerize a Django application](#1-overview-containerize-a-django-application)
- [2. Prerequisites](#2-prerequisites)
- [3. Create the Django project](#3-create-the-django-project)

# 1. Overview: Containerize a Django application

This guide shows how to containerize a Django application using Docker. You'll scaffold the project with `uv`, create a production-ready Dockerfile using a Docker Hardened Image, then add a development stage and Compose Watch for fast iteration.

# 2. Prerequisites

- You have installed the latest version of [Docker Desktop](https://tinyurl.com/2up6tvrk).
- You have [uv](https://tinyurl.com/5bdmvhn4) installed

# 3. Create the Django project

1. Create a project directory named 'django-docker' and navigate to it.
2. Initialize the project in the current directory, pinned to `Python 3.14`:

```bash
uv init --python 3.14 .
```

3. Add Django and Gunicorn, then scaffold the Django project:

```bash
uv add django gunicorn
uv run django-admin startproject config .
```

Your directory should now contain the following files:

```
├── .python-version
├── src/
│ └── docker_django/
│   └── __init__.py
├── manage.py
├── config/
│ ├── __init__.py
│ ├── asgi.py
│ ├── settings.py
│ ├── urls.py
│ └── wsgi.py
├── pyproject.toml
├── uv.lock
└── README.md
```
