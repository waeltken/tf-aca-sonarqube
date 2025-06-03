# Sonarqube on Azure Container Apps

## Quirks

### Elasticsearch

The sonarqube docker container runs a elasticsearch container internally, creates a mutual exclusive lock on the filesystem, and uses a lot of memory. The container will not start if the lock file is present.

This prevents a rolling update of the container requiring a manual deactivation of the previous revision:

```bash
az containerapp revision deactivate -n sonarqube -g sonarqube-rg --revision sonarqube--0000010
```

### Volume Mounts with Azure Files

Currently need specific mount options to run. Consider using NFS instead.
