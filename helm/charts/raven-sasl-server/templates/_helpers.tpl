{{- define "pingmailer-raven-sasl.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "pingmailer-raven-sasl.fullname" -}}
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

{{- define "pingmailer-raven-sasl.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "pingmailer-raven-sasl.labels" -}}
helm.sh/chart: {{ include "pingmailer-raven-sasl.chart" . }}
{{ include "pingmailer-raven-sasl.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: sasl
{{- end }}

{{- define "pingmailer-raven-sasl.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pingmailer-raven-sasl.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "pingmailer-raven-sasl.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "pingmailer-raven-sasl.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Derive oauth_issuer_url from config.oauth.issuerUrl if set,
otherwise from config.domain (https://<domain>:8090).
*/}}
{{- define "pingmailer-raven-sasl.issuerUrl" -}}
{{- if .Values.config.oauth.issuerUrl -}}
{{ .Values.config.oauth.issuerUrl }}
{{- else -}}
https://{{ required "config.domain is required" .Values.config.domain }}:8090
{{- end -}}
{{- end }}

{{/*
Derive oauth_jwks_url similarly.
*/}}
{{- define "pingmailer-raven-sasl.jwksUrl" -}}
{{- if .Values.config.oauth.jwksUrl -}}
{{ .Values.config.oauth.jwksUrl }}
{{- else -}}
https://{{ required "config.domain is required" .Values.config.domain }}:8090/oauth2/jwks
{{- end -}}
{{- end }}
