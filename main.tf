terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=3.0.0"
    }
    kubernetes = {
      version = ">=2.1.0"
    }
    helm = {
      version = ">=2.1.2"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg-webgoat" {
  name     = "rg-webgoat"
  location = "East US"
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "webGoatCluster"
  location            = "Canada Central"
  resource_group_name = "rg-webgoat"
  dns_prefix          = "webgoatk8cluster"

  depends_on = [azurerm_resource_group.rg-webgoat]

  default_node_pool {
    name                 = "default"
    vm_size              = "Standard_B2s"
    auto_scaling_enabled = true
    min_count            = 1
    max_count            = 3
  }

  identity {
    type = "SystemAssigned"
  }

  role_based_access_control_enabled = true

  monitor_metrics {
    annotations_allowed = "prometheus.io/scrape,prometheus.io/path"
    labels_allowed      = "app,environment,version"
  }

  tags = {
    environment = "Develop"
  }
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  }
}

# Create Log analytics workspace
resource "azurerm_monitor_workspace" "amw" {
  name                = "aks-monitor-workspace"
  location            = "Canada Central"
  resource_group_name = "rg-webgoat"
  depends_on          = [azurerm_resource_group.rg-webgoat]
}

resource "azurerm_monitor_data_collection_endpoint" "dce" {
  name                = "dataCollectionEndpoint"
  resource_group_name = "rg-webgoat"
  location            = "Canada Central"
  kind                = "Linux"
  depends_on          = [azurerm_resource_group.rg-webgoat]
}

resource "azurerm_monitor_data_collection_rule" "dcr" {
  name                        = "dataCollectionRule"
  resource_group_name         = "rg-webgoat"
  location                    = "Canada Central"
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce.id
  kind                        = "Linux"

  destinations {
    monitor_account {
      monitor_account_id = azurerm_monitor_workspace.amw.id
      name               = "MonitoringAccount1"
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["MonitoringAccount1"]
  }

  data_sources {
    prometheus_forwarder {
      streams = ["Microsoft-PrometheusMetrics"]
      name    = "PrometheusDataSource"
    }
  }

  description = "DCR for Azure Monitor Metrics Profile (Managed Prometheus)"
  depends_on = [
    azurerm_monitor_data_collection_endpoint.dce,
    azurerm_resource_group.rg-webgoat
  ]
}

resource "azurerm_monitor_data_collection_rule_association" "dcra" {
  name                    = "MSProm"
  target_resource_id      = azurerm_kubernetes_cluster.aks.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.dcr.id
  description             = "Association of data collection rule. Deleting this association will break the data collection for this AKS Cluster."
  depends_on = [
    azurerm_monitor_data_collection_rule.dcr
  ]
}

resource "azurerm_dashboard_grafana" "grafana" {
  name                  = "grafana-prometheus"
  resource_group_name   = "rg-webgoat"
  location              = "Canada Central"
  grafana_major_version = "10"

  depends_on = [azurerm_resource_group.rg-webgoat]

  identity {
    type = "SystemAssigned"
  }

  azure_monitor_workspace_integrations {
    resource_id = azurerm_monitor_workspace.amw.id
  }
}

resource "azurerm_monitor_alert_prometheus_rule_group" "node_recording_rules_rule_group" {
  name                = "NodeRecordingRulesRuleGroup-webGoatCluster"
  location            = "Canada Central"
  resource_group_name = "rg-webgoat"
  cluster_name        = "webGoatCluster"
  description         = "Node Recording Rules Rule Group"
  rule_group_enabled  = true
  interval            = "PT1M"
  scopes              = [azurerm_monitor_workspace.amw.id, azurerm_kubernetes_cluster.aks.id]

  depends_on = [azurerm_resource_group.rg-webgoat]

  rule {
    enabled    = true
    record     = "instance:node_num_cpu:sum"
    expression = <<EOF
count without (cpu, mode) (  node_cpu_seconds_total{job="node",mode="idle"})
EOF
  }
  rule {
    enabled    = true
    record     = "instance:node_cpu_utilisation:rate5m"
    expression = <<EOF
1 - avg without (cpu) (  sum without (mode) (rate(node_cpu_seconds_total{job="node", mode=~"idle|iowait|steal"}[5m])))
EOF
  }
  rule {
    enabled    = true
    record     = "instance:node_load1_per_cpu:ratio"
    expression = <<EOF
(  node_load1{job="node"}/  instance:node_num_cpu:sum{job="node"})
EOF
  }
  rule {
    enabled    = true
    record     = "instance:node_memory_utilisation:ratio"
    expression = <<EOF
1 - (  (    node_memory_MemAvailable_bytes{job="node"}    or    (      node_memory_Buffers_bytes{job="node"}      +      node_memory_Cached_bytes{job="node"}      +      node_memory_MemFree_bytes{job="node"}      +      node_memory_Slab_bytes{job="node"}    )  )/  node_memory_MemTotal_bytes{job="node"})
EOF
  }
}

resource "azurerm_monitor_alert_prometheus_rule_group" "kubernetes_recording_rules_rule_group" {
  name                = "KubernetesRecordingRulesRuleGroup-webGoatCluster"
  location            = "Canada Central"
  resource_group_name = "rg-webgoat"
  cluster_name        = "webGoatCluster"
  description         = "Kubernetes Recording Rules Rule Group"
  rule_group_enabled  = true
  interval            = "PT1M"
  scopes              = [azurerm_monitor_workspace.amw.id, azurerm_kubernetes_cluster.aks.id]

  depends_on = [azurerm_resource_group.rg-webgoat]

  rule {
    enabled    = true
    record     = "node_namespace_pod_container:container_cpu_usage_seconds_total:sum_irate"
    expression = <<EOF
sum by (cluster, namespace, pod, container) (  irate(container_cpu_usage_seconds_total{job="cadvisor", image!=""}[5m])) * on (cluster, namespace, pod) group_left(node) topk by (cluster, namespace, pod) (  1, max by(cluster, namespace, pod, node) (kube_pod_info{node!=""}))
EOF
  }
  rule {
    enabled    = true
    record     = "node_namespace_pod_container:container_memory_working_set_bytes"
    expression = <<EOF
container_memory_working_set_bytes{job="cadvisor", image!=""}* on (namespace, pod) group_left(node) topk by(namespace, pod) (1,  max by(namespace, pod, node) (kube_pod_info{node!=""}))
EOF
  }
  rule {
    enabled    = true
    record     = "cluster:namespace:pod_memory:active:kube_pod_container_resource_requests"
    expression = <<EOF
kube_pod_container_resource_requests{resource="memory",job="kube-state-metrics"}  * on (namespace, pod, cluster)group_left() max by (namespace, pod, cluster) (  (kube_pod_status_phase{phase=~"Pending|Running"} == 1))
EOF
  }
  rule {
    enabled    = true
    record     = "cluster:namespace:pod_cpu:active:kube_pod_container_resource_requests"
    expression = <<EOF
kube_pod_container_resource_requests{resource="cpu",job="kube-state-metrics"}  * on (namespace, pod, cluster)group_left() max by (namespace, pod, cluster) (  (kube_pod_status_phase{phase=~"Pending|Running"} == 1))
EOF
  }
  rule {
    enabled    = true
    record     = "cluster:namespace:pod_cpu:active:kube_pod_container_resource_limits"
    expression = <<EOF
kube_pod_container_resource_limits{resource="cpu",job="kube-state-metrics"}  * on (namespace, pod, cluster)group_left() max by (namespace, pod, cluster) ( (kube_pod_status_phase{phase=~"Pending|Running"} == 1) )
EOF
  }
  rule {
    enabled    = true
    record     = "namespace_cpu:kube_pod_container_resource_limits:sum"
    expression = <<EOF
sum by (namespace, cluster) (    sum by (namespace, pod, cluster) (        max by (namespace, pod, container, cluster) (          kube_pod_container_resource_limits{resource="cpu",job="kube-state-metrics"}        ) * on(namespace, pod, cluster) group_left() max by (namespace, pod, cluster) (          kube_pod_status_phase{phase=~"Pending|Running"} == 1        )    ))
EOF
  }
  rule {
    enabled    = true
    record     = "cluster:node_cpu:ratio_rate5m"
    expression = <<EOF
sum(rate(node_cpu_seconds_total{job="node",mode!="idle",mode!="iowait",mode!="steal"}[5m])) by (cluster) /count(sum(node_cpu_seconds_total{job="node"}) by (cluster, instance, cpu)) by (cluster)
EOF
  }
}

resource "grafana_contact_point" "contact_point" {
  name = "Grafana Discord Alerts"

  discord {
    url = "https://discord.com/api/webhooks/1315056781248172064/oLlUZgFBHnyBcLM3mOoTJ8C4wx4uFbnTFKPh4_E8WIKgfrAisxgzHB-Nnih5uAtPgU43"
    message = "{{ len .Alerts.Firing }} new metric alert!"
  }
}

resource "helm_release" "kubecost" {
  name             = "kubecost"
  chart            = "cost-analyzer"
  repository       = "https://kubecost.github.io/cost-analyzer/"
  create_namespace = true

  set {
    name  = "kubecostProductConfigs.clusterName"
    value = "webGoatCluster"
  }

  set {
    name  = "kubecostProductConfigs.currencyCode"
    value = "CAD"
  }
}
