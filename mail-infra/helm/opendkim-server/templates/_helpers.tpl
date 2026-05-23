{{/*
Expand the name of the chart.
*/}}
{{- define "silver-opendkim.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name.
*/}}
{{- define "silver-opendkim.fullname" -}}
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
{{- define "silver-opendkim.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "silver-opendkim.labels" -}}
helm.sh/chart: {{ include "silver-opendkim.chart" . }}
{{ include "silver-opendkim.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: opendkim
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "silver-opendkim.selectorLabels" -}}
app.kubernetes.io/name: {{ include "silver-opendkim.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name.
*/}}
{{- define "silver-opendkim.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "silver-opendkim.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
PVC claim name (existing or chart-managed).
*/}}
{{- define "silver-opendkim.claimName" -}}
{{- if .Values.persistence.existingClaim }}
{{- .Values.persistence.existingClaim }}
{{- else }}
{{- printf "%s-keys" (include "silver-opendkim.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Normalize a single domain entry to a dict with domain/selector/keySize.
Pass the entry as the context.
*/}}
{{- define "silver-opendkim.domain" -}}
{{- $entry := . -}}
{{- $selector := default "mail" $entry.selector -}}
{{- $keySize := default 2048 $entry.keySize -}}
domain: {{ $entry.domain }}
selector: {{ $selector }}
keySize: {{ $keySize }}
{{- end }}
