{{- define "silver-thunder.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "silver-thunder.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "silver-thunder.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "silver-thunder.labels" -}}
helm.sh/chart: {{ include "silver-thunder.chart" . }}
app.kubernetes.io/name: {{ include "silver-thunder.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: thunder
{{- end }}

{{/*
Name of the bootstrap ConfigMap. Hardcoded so the value referenced by the
subchart (thunderid.bootstrap.configMap.name in values.yaml) is consistent
no matter how users override the release name.
*/}}
{{- define "silver-thunder.bootstrapConfigMapName" -}}
thunder-bootstrap
{{- end }}
