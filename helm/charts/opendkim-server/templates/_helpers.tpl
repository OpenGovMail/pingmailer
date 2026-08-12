{{/*
Expand the name of the chart.
*/}}
{{- define "opengovmail-opendkim.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name.
*/}}
{{- define "opengovmail-opendkim.fullname" -}}
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

{{/*
Chart label.
*/}}
{{- define "opengovmail-opendkim.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "opengovmail-opendkim.labels" -}}
helm.sh/chart: {{ include "opengovmail-opendkim.chart" . }}
{{ include "opengovmail-opendkim.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: opendkim
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "opengovmail-opendkim.selectorLabels" -}}
app.kubernetes.io/name: {{ include "opengovmail-opendkim.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name.
*/}}
{{- define "opengovmail-opendkim.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "opengovmail-opendkim.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
PVC claim name (existing or chart-managed).
*/}}
{{- define "opengovmail-opendkim.claimName" -}}
{{- if .Values.persistence.existingClaim }}
{{- .Values.persistence.existingClaim }}
{{- else }}
{{- printf "%s-keys" (include "opengovmail-opendkim.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Normalize a single domain entry to a dict with domain/selector/keySize.
Pass the entry as the context.
*/}}
{{- define "opengovmail-opendkim.domain" -}}
{{- $entry := . -}}
{{- $selector := default "mail" $entry.selector -}}
{{- $keySize := default 2048 $entry.keySize -}}
domain: {{ $entry.domain }}
selector: {{ $selector }}
keySize: {{ $keySize }}
{{- end }}
