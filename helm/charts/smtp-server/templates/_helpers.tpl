{{- define "opengovmail-smtp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "opengovmail-smtp.fullname" -}}
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

{{- define "opengovmail-smtp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "opengovmail-smtp.labels" -}}
helm.sh/chart: {{ include "opengovmail-smtp.chart" . }}
{{ include "opengovmail-smtp.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: smtp
{{- end }}

{{- define "opengovmail-smtp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "opengovmail-smtp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "opengovmail-smtp.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "opengovmail-smtp.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Resolved postfix hostname: explicit `hostname` value, or `mail.<domain>`.
*/}}
{{- define "opengovmail-smtp.hostname" -}}
{{- if .Values.hostname -}}
{{ .Values.hostname }}
{{- else -}}
mail.{{ required "domain is required" .Values.domain }}
{{- end -}}
{{- end }}

{{/*
PVC claim name for the postfix spool.
*/}}
{{- define "opengovmail-smtp.spoolClaim" -}}
{{- if .Values.persistence.spool.existingClaim }}
{{- .Values.persistence.spool.existingClaim }}
{{- else }}
{{- printf "%s-spool" (include "opengovmail-smtp.fullname" .) }}
{{- end }}
{{- end }}
