{{- define "pingmailer-smtp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "pingmailer-smtp.fullname" -}}
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

{{- define "pingmailer-smtp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "pingmailer-smtp.labels" -}}
helm.sh/chart: {{ include "pingmailer-smtp.chart" . }}
{{ include "pingmailer-smtp.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: smtp
{{- end }}

{{- define "pingmailer-smtp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pingmailer-smtp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "pingmailer-smtp.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "pingmailer-smtp.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Resolved postfix hostname: explicit `hostname` value, or `mail.<domain>`.
*/}}
{{- define "pingmailer-smtp.hostname" -}}
{{- if .Values.hostname -}}
{{ .Values.hostname }}
{{- else -}}
mail.{{ required "domain is required" .Values.domain }}
{{- end -}}
{{- end }}

{{/*
PVC claim name for the postfix spool.
*/}}
{{- define "pingmailer-smtp.spoolClaim" -}}
{{- if .Values.persistence.spool.existingClaim }}
{{- .Values.persistence.spool.existingClaim }}
{{- else }}
{{- printf "%s-spool" (include "pingmailer-smtp.fullname" .) }}
{{- end }}
{{- end }}
