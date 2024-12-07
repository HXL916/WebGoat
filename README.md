# WebGoat: A deliberately insecure Web Application

[![Build](https://github.com/WebGoat/WebGoat/actions/workflows/build.yml/badge.svg?branch=develop)](https://github.com/WebGoat/WebGoat/actions/workflows/build.yml)
[![java-jdk](https://img.shields.io/badge/java%20jdk-21-green.svg)](https://jdk.java.net/)
[![OWASP Labs](https://img.shields.io/badge/OWASP-Lab%20project-f7b73c.svg)](https://owasp.org/projects/)
[![GitHub release](https://img.shields.io/github/release/WebGoat/WebGoat.svg)](https://github.com/WebGoat/WebGoat/releases/latest)
[![Gitter](https://badges.gitter.im/OWASPWebGoat/community.svg)](https://gitter.im/OWASPWebGoat/community?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)
[![Discussions](https://img.shields.io/github/discussions/WebGoat/WebGoat)](https://github.com/WebGoat/WebGoat/discussions)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-%23FE5196?logo=conventionalcommits&logoColor=white)](https://conventionalcommits.org)

## SonarCloud

[![SonarCloud](https://sonarcloud.io/images/project_badges/sonarcloud-white.svg)](https://sonarcloud.io/summary/new_code?id=LOG8100_WebGoat)<br>
[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=LOG8100_WebGoat&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=LOG8100_WebGoat)  
[![Coverage](https://sonarcloud.io/api/project_badges/measure?project=LOG8100_WebGoat&metric=coverage)](https://sonarcloud.io/summary/new_code?id=LOG8100_WebGoat)  
[![Reliability Rating](https://sonarcloud.io/api/project_badges/measure?project=LOG8100_WebGoat&metric=reliability_rating)](https://sonarcloud.io/summary/new_code?id=LOG8100_WebGoat)

## Introduction

This repository is a **school project** for the course _LOG8100: DevSecOps - Opérations et dév. logiciel sécur_ and focuses on the integration of CI/CD pipelines and security best practices in Kubernetes environments. The project builds upon the original WebGoat repository by integrating additional workflows for a secure, automated deployment process in Kubernetes.

## CI/CD pipeline steps

The pipeline is triggered when a **deployment** event is happening.

### Docker Image build and vulnerability scan

The first step in the pipeline is to build the project and create a Docker image.  
Afterwards, we perform a vulnerability scan on the image using Trivy and push the image to Docker Hub. The result of the Trivy scan is uploaded as an artifact and will remain in the repository for 30 days (Usually we would stop the deployment if the scan found any **High** or **Critical** vulnerabilities but here we continue the deployment to prove that our CI/CD pipeline works).

### Deploy AKS Cluster with Terraform

After pushing the new version of our Docker image to the Docker Hub, we log in to Azure using a service principal. Once logged in, we verify if there's already an existing AKS and workspace resources from a previous deployment and delete them if they exist (we could also choose to keep the previous deployment in case we introduced a problem and need to do a rollback but here we delete the previous resources because we have limited Azure credits).  
Once the previous resources are deleted, we initialize Terraform and validate the script configuration in _main.tf_ before applying it to deploy the AKS cluster.

### Deploy Docker container with Ansible

Once the AKS cluster is deployed, we install Ansible and the required collections in the VM running the workflow and we use the Ansible playbook _azure_configure_aks.yml_ to deploy the Docker container to the AKS cluster using the image we pushed to Docker Hub in the first step as well as install **Prometheus** and **Grafana** and set them up to monitor the new AKS cluster.

## Kubernetes Cluster configuration

Cluster details:

-   Name: `webGoatCluster`
-   Region: `Canada Central`
-   VM Size: `Standard_B1ms`
-   Auto-scaling: between 1 and 3 nodes based on traffic

Log Analytics:

-   A log analytics workspace (`aks-log-workspace`) is created for monitoring

## Terraform manual installation

The execution of the Terraform script is entirely automated in the Github Action but if you need to run it locally for any reason here are the recommended steps:

-   Install the latest version of Terraform CLI
-   Initializes a working directory to use with Terraform using `terraform init`
-   Optionally, use `terraform validate` to check the configuration file for syntax errors
-   Optionally, run `terraform plan` to preview the changes Terraform will make to your infrastructure before applying them
-   Finally, apply the changes using `terraform apply`

When running `terraform init`, `terraform plan` and `terraform apply`, you need to pass some variables which are needed for the script to log in to Azure. Before running these commands, get the following secrets and store them in a `.tfvars` file:

```
ARM_SUBSCRIPTION_ID="your-subscription-id"
ARM_CLIENT_ID="your-client-id"
ARM_CLIENT_SECRET="your-client-secret"
ARM_TENANT_ID="your-tenant-id"
```

Afterwards, you can run the command with `terraform init -var-file="terraform.tfvars"`
