{{/*
Calculate the domain based on project name, environment, and global zone.
*/}}
{{- define "project.domain" -}}
{{- if eq .Values.werf.env "prod" -}}
  {{ .Values.global.domainOverride | default (printf "%s-%s.%s" .Values.werf.name .Values.werf.env .Values.global.zone) }}
{{- else -}}
  {{- printf "%s-%s.%s" .Values.werf.name .Values.werf.env .Values.global.zone -}}
{{- end -}}
{{- end -}}

{{- define "deployment.configmap" -}}
{{- if eq .Values.werf.env "prod" -}}
checksum/configmap-mainconf: '{{ include (print $.Template.BasePath "/configmap-config-prod.yaml") . | sha256sum }}'
{{- else -}}
checksum/configmap-mainconf: '{{ include (print $.Template.BasePath "/configmap-config-dev.yaml") . | sha256sum }}'
{{- end -}}
{{- end -}}

{{- define "rabbitmq.livenessProbe" -}}
livenessProbe:
  exec:
    command: ["rabbitmq-diagnostics", "ping"]
  initialDelaySeconds: 20
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
{{- end }}

{{- define "rabbitmq.readinessProbe" -}}
readinessProbe:
  exec:
    command: ["rabbitmq-diagnostics", "check_running"]
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
{{- end }}

{{- define "mongo.livenessProbe" }}
livenessProbe:
  exec:
    command:
      - mongo
      - --eval
      - "db.adminCommand('ping')"
  initialDelaySeconds: 10
  periodSeconds: 10
{{- end }}

{{- define "mongo.readinessProbe" }}
readinessProbe:
  exec:
    command:
      - mongo
      - --username
      - {{ .Values.services.mongo.userName }}
      - --password
      - {{ .Values.services.mongo.userPassword }}
      - --authenticationDatabase
      - admin
      - --eval
      - "db.adminCommand('ping')"
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 5
  failureThreshold: 3
{{- end }}

{{- define "anotations" }}
{{- end }}

{{- define "image.secrets" }}
imagePullSecrets:
  - name: registry
{{- end }}

{{- define "node.selector" }}
{{ if eq .Values.environment "prod" }}
nodeSelector:
{{- end }}
{{- end }}

{{- define "node.tolerations" }}
{{ if eq .Values.environment "prod" }}
tolerations:
{{- end }}
{{- end }}

{{- define "healthcheck" }}
{{- end }}