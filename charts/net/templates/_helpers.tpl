{{/*
Expand the name of the chart.
*/}}
{{- define "hanzo-net.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "hanzo-net.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "hanzo-net.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "hanzo-net.labels" -}}
helm.sh/chart: {{ include "hanzo-net.chart" . }}
{{ include "hanzo-net.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "hanzo-net.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hanzo-net.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "hanzo-net.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "hanzo-net.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Controller fully qualified name
*/}}
{{- define "hanzo-net.controller.fullname" -}}
{{- printf "%s-controller" (include "hanzo-net.fullname" .) }}
{{- end }}

{{/*
Router fully qualified name
*/}}
{{- define "hanzo-net.router.fullname" -}}
{{- printf "%s-router" (include "hanzo-net.fullname" .) }}
{{- end }}

{{/*
Controller internal endpoint (for router enrollment)
*/}}
{{- define "hanzo-net.controller.endpoint" -}}
{{- if .Values.router.enrollment.controllerEndpoint }}
{{- .Values.router.enrollment.controllerEndpoint }}
{{- else }}
{{- printf "%s:%d" (include "hanzo-net.controller.fullname" .) (int .Values.controller.service.port) }}
{{- end }}
{{- end }}
