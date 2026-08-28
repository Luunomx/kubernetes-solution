# Security policy

## Reporting a vulnerability

Please do not open a public issue for a suspected credential leak or exploitable vulnerability. Contact the repository owner privately and include enough detail to reproduce the issue without sharing live credentials.

## Secret handling

This repository contains templates only. Runtime credentials belong in local environment files, Kubernetes Secrets provisioned by a secret manager, or CI/CD secret storage. If a credential has ever been committed, revoke or rotate it first; deleting it from the latest commit is not sufficient because Git history remains recoverable.
