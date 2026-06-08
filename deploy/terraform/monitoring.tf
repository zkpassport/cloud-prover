# Observability via the standard Google Cloud console — no Prometheus.
#
# The handler emits one structured `proof_generated` log line per proof. From it
# we derive log-based distribution metrics (one per timing segment) plus a count,
# and assemble a Cloud Monitoring dashboard. Per-proof splits are visible in the
# dashboard's logs panel (and Logs Explorer).

locals {
  # segment -> jsonPayload field
  proof_segments = {
    total       = "total_ms"       # end-to-end request time
    bb_prove    = "bb_prove_ms"    # the bb prove step
    witness_gen = "witness_gen_ms" # Node-side witness generation (null when witness is provided)
  }

  proof_log_filter = <<-EOT
    resource.type="k8s_container"
    resource.labels.namespace_name="zkpassport-cloud-prover"
    jsonPayload.event="proof_generated"
  EOT
}

# One distribution metric per timing segment, labelled by circuit + evm.
resource "google_logging_metric" "proof_segment" {
  for_each = local.proof_segments

  name    = "cloud_prover/proof_${each.key}_ms"
  project = var.project_id
  filter  = local.proof_log_filter

  value_extractor = "EXTRACT(jsonPayload.${each.value})"

  label_extractors = {
    "circuit_name" = "EXTRACT(jsonPayload.circuit_name)"
    "evm"          = "EXTRACT(jsonPayload.evm)"
  }

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "DISTRIBUTION"
    unit        = "ms"
    labels {
      key        = "circuit_name"
      value_type = "STRING"
    }
    labels {
      key        = "evm"
      value_type = "BOOL"
    }
  }

  bucket_options {
    exponential_buckets {
      num_finite_buckets = 64
      growth_factor      = 1.15
      scale              = 1000 # ms; ~1s up through several minutes
    }
  }
}

# Simple counter for throughput (count of proofs).
resource "google_logging_metric" "proof_count" {
  name    = "cloud_prover/proof_count"
  project = var.project_id
  filter  = local.proof_log_filter

  label_extractors = {
    "circuit_name" = "EXTRACT(jsonPayload.circuit_name)"
    "evm"          = "EXTRACT(jsonPayload.evm)"
  }

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    labels {
      key        = "circuit_name"
      value_type = "STRING"
    }
    labels {
      key        = "evm"
      value_type = "BOOL"
    }
  }
}

locals {
  metric_total       = "logging.googleapis.com/user/cloud_prover/proof_total_ms"
  metric_bb_prove    = "logging.googleapis.com/user/cloud_prover/proof_bb_prove_ms"
  metric_witness_gen = "logging.googleapis.com/user/cloud_prover/proof_witness_gen_ms"
  metric_count       = "logging.googleapis.com/user/cloud_prover/proof_count"
}

resource "google_monitoring_dashboard" "cloud_prover" {
  project = var.project_id

  dashboard_json = jsonencode({
    displayName = "Cloud Prover"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          xPos = 0, yPos = 0, width = 6, height = 4
          widget = {
            title = "Proof duration p50 / p95 (ms)"
            xyChart = {
              dataSets = [
                {
                  legendTemplate = "p50"
                  timeSeriesQuery = { timeSeriesFilter = {
                    filter      = "metric.type=\"${local.metric_total}\" resource.type=\"k8s_container\""
                    aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_PERCENTILE_50" }
                  } }
                },
                {
                  legendTemplate = "p95"
                  timeSeriesQuery = { timeSeriesFilter = {
                    filter      = "metric.type=\"${local.metric_total}\" resource.type=\"k8s_container\""
                    aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_PERCENTILE_95" }
                  } }
                },
              ]
            }
          }
        },
        {
          xPos = 6, yPos = 0, width = 6, height = 4
          widget = {
            title = "Step breakdown p50 (ms): witness_gen / bb_prove / total"
            xyChart = {
              dataSets = [
                { legendTemplate = "witness_gen", timeSeriesQuery = { timeSeriesFilter = {
                  filter      = "metric.type=\"${local.metric_witness_gen}\" resource.type=\"k8s_container\""
                  aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_PERCENTILE_50" }
                } } },
                { legendTemplate = "bb_prove", timeSeriesQuery = { timeSeriesFilter = {
                  filter      = "metric.type=\"${local.metric_bb_prove}\" resource.type=\"k8s_container\""
                  aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_PERCENTILE_50" }
                } } },
                { legendTemplate = "total", timeSeriesQuery = { timeSeriesFilter = {
                  filter      = "metric.type=\"${local.metric_total}\" resource.type=\"k8s_container\""
                  aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_PERCENTILE_50" }
                } } },
              ]
            }
          }
        },
        {
          xPos = 0, yPos = 4, width = 6, height = 4
          widget = {
            title = "Median proof time by circuit (ms)"
            xyChart = {
              dataSets = [{ timeSeriesQuery = { timeSeriesFilter = {
                filter = "metric.type=\"${local.metric_total}\" resource.type=\"k8s_container\""
                aggregation = {
                  alignmentPeriod    = "300s"
                  perSeriesAligner   = "ALIGN_PERCENTILE_50"
                  crossSeriesReducer = "REDUCE_MEAN"
                  groupByFields      = ["metric.label.circuit_name"]
                }
              } } }]
            }
          }
        },
        {
          xPos = 6, yPos = 4, width = 6, height = 4
          widget = {
            title = "Proofs per interval"
            xyChart = {
              dataSets = [{ timeSeriesQuery = { timeSeriesFilter = {
                filter = "metric.type=\"${local.metric_count}\" resource.type=\"k8s_container\""
                aggregation = {
                  alignmentPeriod    = "300s"
                  perSeriesAligner   = "ALIGN_DELTA"
                  crossSeriesReducer = "REDUCE_SUM"
                  groupByFields      = ["metric.label.evm"]
                }
              } } }]
            }
          }
        },
        {
          xPos = 0, yPos = 8, width = 12, height = 5
          widget = {
            title = "Recent proofs (per-proof splits)"
            logsPanel = {
              filter        = "resource.type=\"k8s_container\"\nresource.labels.namespace_name=\"zkpassport-cloud-prover\"\njsonPayload.event=\"proof_generated\""
              resourceNames = ["projects/${var.project_id}"]
            }
          }
        },
      ]
    }
  })

  depends_on = [
    google_logging_metric.proof_segment,
    google_logging_metric.proof_count,
  ]
}
