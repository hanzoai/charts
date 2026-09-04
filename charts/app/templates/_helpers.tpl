{{/*
Name. Equals the App CR's metadata.name, which equals the release name under the
ApplicationSet. Overridable so a chart consumer outside the fleet can pick their own.
*/}}
{{- define "app.name" -}}
{{- .Values.nameOverride | default .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Selector labels — LOAD BEARING, DO NOT ADD TO THIS SET.

`spec.selector` on a Deployment and `spec.selector` on a StatefulSet are IMMUTABLE.
Adding a label here does not produce a diff — it produces an apply the apiserver
rejects. Version in particular must stay OUT: it changes on every image bump.

`selectorLabels` exists because that immutability cuts both ways. A workload that
already runs with a DIFFERENT selector — `app: x`, or `k8s-app: x`, which is most
of the Lux, Zoo and Pars fleets — cannot be adopted by a chart that insists on its
own scheme. The only alternatives were to recreate 230 running workloads for a
label, or to let the chart state the selector the object actually has.

So the selector is treated as what it is: a fact OF THE OBJECT, not a policy of
the chart. Empty means the standard two labels, which is what every new service
gets. A values file setting it is recording history, and the honest place for that
history is the values file rather than a footnote in a runbook.

These labels are the selector ONLY. The full label set on metadata stays the
chart's, so an adopted workload still gains name/instance/part-of/managed-by for
everything that reads labels without selecting on them.
*/}}
{{- define "app.selectorLabels" -}}
{{- if .Values.selectorLabels -}}
{{ toYaml .Values.selectorLabels }}
{{- else -}}
app.kubernetes.io/name: {{ include "app.name" . }}
app.kubernetes.io/instance: {{ include "app.name" . }}
{{- end -}}
{{- end -}}

{{/*
Full label set for object metadata. Free to grow — none of these are selectors.
`version` tracks the image tag, matching what the operator stamped.
*/}}
{{- define "app.labels" -}}
{{ include "app.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.partOf }}
app.kubernetes.io/part-of: {{ . }}
{{- end }}
{{- with .Values.component }}
app.kubernetes.io/component: {{ . }}
{{- end }}
{{- with include "app.version" . }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
{{- with .Values.labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/*
Version label = image tag, sanitized to a legal label value. A digest pin has no
tag, so this yields empty and the label is omitted rather than emitted invalid.
*/}}
{{- define "app.version" -}}
{{- $t := .Values.image.tag | default "" | toString -}}
{{- if $t }}{{ $t | replace ":" "_" | trunc 63 | trimSuffix "-" }}{{ end -}}
{{- end -}}

{{/*
Image reference. A digest wins over a tag when both are set.
*/}}
{{- define "app.image" -}}
{{- $r := required "image.repository is required" .Values.image.repository -}}
{{- /* A CLAIMED NAME IS A RELEASE, OR IT IS NOT A REFERENCE.

       ../claimed lists the image names whose versions exactly one pipeline
       mints — read that file first; it carries the reasoning and it is the only
       place the list lives. For those, the pin has to BE one of the names the
       owner hands out: the same v<semver> shape pipeline-only-releases.yaml
       refuses to let anything else publish, plus the digest that names its
       bytes.

       Here, because here is where an image reference is MADE. pin.sh already
       refuses to write a sha and pins.py already reports one, and production
       still ran ghcr.io/hanzoai/cloud:sha-69f9ac2 for a day: the first governs
       one writer and the second only speaks in CI, while cd renders whatever
       main says. Every path to a running pod goes through this helper, so a
       refusal here is the one that cannot be gone around. The render stops, no
       Deployment is produced, prune is off, and the pods keep serving the
       release they were last given — a failed sync that changes nothing, which
       is the correct outcome for a pin nobody can trace. */ -}}
{{- $ctx := . -}}
{{- /* Read the claim list ONCE, and refuse to render if it is not there.
       Reading it inline meant an absent, empty or all-comment file produced no
       iterations and therefore no refusals — the guard passed every pin, and
       the only thing that noticed was a CI job, which is the mechanism this
       exists because it does not deploy. A control that cannot be read is not a
       control, so it fails closed. */ -}}
{{- $claims := list -}}
{{- range $line := splitList "\n" ($ctx.Files.Get "claimed") -}}
{{- $c := trim (regexReplaceAll "#.*$" $line "") -}}
{{- if $c -}}{{- $claims = append $claims $c -}}{{- end -}}
{{- end -}}
{{- if not $claims -}}
{{- fail "charts/app/claimed is missing, empty, or entirely comments, so no image name has an owner and every pin would render unchecked. It is packaged with this chart; if it is absent the chart was assembled wrong. Restore it rather than removing the names from it" -}}
{{- end -}}
{{- /* A repository names a PATH. Carrying a tag or a digest in it is how the
       reference gets assembled somewhere this helper cannot see: with
       `repository: ghcr.io/hanzoai/cloud:v1.801.511` the suffix below never
       matched, so a foreign digest rendered under a release name — the exact
       pair this guard exists to keep together. */ -}}
{{- if or (contains ":" $r) (contains "@" $r) -}}
{{- fail (printf "image.repository is %q, which carries a tag or a digest. A repository is a path; the version belongs in image.tag and the bytes in image.digest, because that is where every check reads them" $r) -}}
{{- end -}}
{{- range $c := $claims -}}
{{- /* Compare against a leading-slash form so the claim's path matches whether
       or not a registry host is written. `hanzoai/cloud` with the host dropped
       resolves to Docker Hub, where that name is real and is not ours. */ -}}
{{- if hasSuffix (first (splitList ":" $c)) (printf "/%s" $r) -}}
{{- $t := $ctx.Values.image.tag | default "" | toString -}}
{{- if not (regexMatch (printf "^%s$" (last (splitList ":" $c))) $t) -}}
{{- fail (printf "%s is pinned at '%s', which is not a release name. This image's versions are minted by the `image` job of its own repo's .hanzo/workflows/cicd.yml, which claims refs/tags/v<N> before it builds and smokes the bytes it will pin. A tag from any other lane names a commit nothing recorded and a build nothing can repeat, so there is no source to read it back from and no version to roll back to. Move the pin with charts/app/pin.sh <service> <version>, which resolves the tag and its digest in one read. charts/app/claimed is where this name's owner is declared" $r $t) -}}
{{- end -}}
{{- if not $ctx.Values.image.digest -}}
{{- fail (printf "%s is pinned at '%s' with no digest. A registry tag is mutable and pullPolicy is IfNotPresent, so the tag says which release and only the digest says which bytes — re-push the tag and the fleet splits across two of them under one version, invisibly. charts/app/pin.sh writes both from one registry read; they cannot disagree if they are never asked twice" $r $ctx.Values.image.tag) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- /* When both are set the digest is what gets pulled and the tag is how a
       human reads it. A digest-only reference is unambiguous and unreadable —
       you cannot tell which version is running by looking, which is how a pin
       drifts unnoticed. Trim markers throughout: this helper yields a scalar,
       so a stray newline lands inside the image string.

       ⚠️ The tag beside a digest must be the one the VALUES declare, never
       .Chart.AppVersion. This previously read

           $t := .Values.image.tag | default .Chart.AppVersion
           if and .Values.image.digest $t   ->  repo:$t@digest

       and since AppVersion is always set, $t was never empty: the digest-only
       branch below could not be reached, and every digest-pinned service got
       the CHART's version stamped onto an unrelated image. Live proof —
       enso and zen both ran `ghcr.io/hanzoai/{enso,zen}:0.1.0@sha256:…` where
       0.1.0 is this chart's appVersion and says nothing about either service.
       A label that looks like a version and is not one is worse than no label,
       because it reads as a pin and drifts silently.

       So: the tag half is EXPLICIT-ONLY. The AppVersion fallback survives on
       the tag-only path, where it is a real default rather than a fiction. */ -}}
{{- if and .Values.image.digest .Values.image.tag -}}
{{ $r }}:{{ .Values.image.tag }}@{{ .Values.image.digest }}
{{- else if .Values.image.digest -}}
{{ $r }}@{{ .Values.image.digest }}
{{- else -}}
{{ $r }}:{{ .Values.image.tag | default .Chart.AppVersion }}
{{- end -}}
{{- end -}}

{{/*
The pod's identity. ONE derivation, because it used to be two keys that never
learned about each other.

`rbac.serviceAccountName` CREATES a ServiceAccount and binds roles to it.
`serviceAccountName` ATTACHES an identity to the pod. Nothing connected them, so
a values file could declare cluster permissions, get a correct ServiceAccount
and a correct ClusterRoleBinding, and still run its pods as `default` — the one
identity guaranteed to hold none of those permissions.

That failure is invisible everywhere you would look for it. The render is clean,
the diff is clean, RBAC exists and `auth can-i --as=` says yes. The only symptom
is a 403 the workload gets at runtime and usually swallows. Measured 2026-08-08:
otel-agent on lux-k8s and zoo-k8s had kubeletstats refused by every kubelet on
both clusters for as long as the agent had existed. hostmetrics reads /hostfs and
needs no API identity, so the agent stayed Ready, kept shipping host series, and
simply never produced one `k8s.node.*` sample. hanzo-k8s was unaffected only
because its agent is a raw manifest that names the account inline.

The keys still mean different things and both survive: `serviceAccountName` names
an identity the chart does NOT own (created by another manifest), `rbac.create`
makes its own. What changes is that declaring the second is now sufficient.
Setting both to DIFFERENT names is incoherent — a pod has one identity — and
fails the render rather than resolving to whichever template read which key.
*/}}
{{- define "app.serviceAccountName" -}}
{{- $rbac := "" -}}
{{- if .Values.rbac -}}{{- $rbac = .Values.rbac.serviceAccountName | default "" -}}{{- end -}}
{{- $named := .Values.serviceAccountName | default "" -}}
{{- if and $rbac $named (ne $rbac $named) -}}
{{- fail (printf "this pod is given two identities: serviceAccountName %q (an account the chart does not own) and rbac.serviceAccountName %q (one it does). A pod has one. Drop serviceAccountName, or make the two names match." $named $rbac) -}}
{{- end -}}
{{- $n := $rbac | default $named -}}
{{- /* An rbac block with no name at all still needs one to hang the objects on,
       and the release name is the only answer that cannot collide with another
       app in the namespace. Outside an rbac block the empty string is correct:
       it means "no identity was asked for", and the field is then not emitted. */ -}}
{{- if and (not $n) .Values.rbac -}}{{- $n = include "app.name" . -}}{{- end -}}
{{- $n -}}
{{- end -}}

{{/*
Workload kind. Anything that keeps state on disk is a StatefulSet; everything
else is a Deployment. Derived rather than declared so the two cannot disagree.
*/}}
{{- define "app.workloadKind" -}}
{{- if .Values.workload.kind -}}
{{ .Values.workload.kind }}
{{- else if or .Values.persistence.enabled .Values.volumeClaimTemplates -}}
StatefulSet
{{- else -}}
Deployment
{{- end -}}
{{- end -}}

{{/*
Does this declaration carry a container?

`image.repository` empty means NO — no workload, no selector, no Service selector.
That is what lets one chart also own the declarations that are not services: a set
of Ingresses for a domain list, a KMS secret reference, a claim, a routing rule, a
Service with no pods behind it. Those were the 18 files in the CR directory that
carried no App at all, and the reason a second delivery path survived is that the
chart insisted on a container.

Derived from the one field that decides it, so a values file cannot declare a
workload and then contradict itself. `values.schema.json` requires a declaration to
carry at least one of image/ports/claims/kmsSecrets/routes/middlewares/ingress, so
an empty or mistyped file fails the render rather than silently owning nothing.
*/}}
{{- define "app.hasWorkload" -}}
{{- if .Values.image.repository }}true{{ end -}}
{{- end -}}

{{/*
Does the pod mount a real PersistentVolumeClaim? Gates surge co-location, below.
*/}}
{{- define "app.mountsClaim" -}}
{{- if or .Values.persistence.enabled .Values.volumeClaimTemplates -}}
true
{{- else -}}
{{- range .Values.volumes }}{{ if .persistentVolumeClaim }}true{{ end }}{{ end -}}
{{- end -}}
{{- end -}}

{{/*
Pod affinity.

`affinity` is the general passthrough. `surgeColocation` is the ONE derived case:
a soft self-podAffinity that pins a rolling surge pod to the node already holding
the app's ReadWriteOnce volume, so it bind-mounts the attached volume instead of
dead-locking on Multi-Attach — a rolling update over a single block volume becomes
a same-host handoff.

It is derived rather than hand-written because the SAFETY GATE is the point. The
brief two-pod overlap is only sound for a store that tolerates concurrent same-host
opens (SQLite in WAL mode with a busy_timeout); an exclusive-lock engine must use
strategy Recreate instead. So the affinity is injected only when the strategy is a
RollingUpdate AND the pod actually mounts a claim, and a values file that asks for
it under Recreate gets nothing rather than a hazard. Writing the affinity by hand
would carry the ten lines and lose the gate.

Both keys write .spec.template.spec.affinity, so setting both is a defect, not a
merge order to learn: the render FAILS instead of picking one.

And `surgeColocation: true` under `strategy: Recreate` FAILS too, which is new.
Refusing to emit the affinity there was always right — the overlap is only sound
for a store that tolerates concurrent same-host opens, so an exclusive-lock
engine belongs on Recreate. But refusing SILENTLY is what made this expensive:
charts/app/values/hanzo/iam.yaml declared `surgeColocation: true` and cancelled
it with `strategy: Recreate` twelve lines earlier, so hanzo.id took a full
identity outage on EVERY tag bump — Recreate tears the old pod down before the
new one is admitted — while the values file read as though a zero-downtime
handover was configured. Nothing rendered wrong; nothing was ever going to say
so. The file was fixed on 2026-08-07; this is so the next one cannot happen.

"Gets nothing rather than a hazard" is safe against the hazard and silent about
the intent, and those are different properties. The gate stays; the silence goes.
Declaring both is incoherent — a store that needs Recreate should not ask for a
surge — so there is no case to preserve.
*/}}
{{- define "app.affinity" -}}
{{- if and .Values.affinity .Values.surgeColocation -}}
{{- fail "affinity and surgeColocation both write spec.template.spec.affinity — declare one" -}}
{{- end -}}
{{- if and .Values.surgeColocation (eq .Values.strategy "Recreate") -}}
{{- fail "surgeColocation: true with strategy: Recreate renders NOTHING — Recreate tears the old pod down before the new one is admitted, so this asks for a zero-downtime handover and gets a full outage on every deploy. Set strategy: RollingUpdate to get the same-host surge, or drop surgeColocation if this store cannot tolerate a two-pod overlap." -}}
{{- end -}}
{{- if .Values.affinity -}}
{{ toYaml .Values.affinity }}
{{- else if and .Values.surgeColocation (ne .Values.strategy "Recreate") (include "app.mountsClaim" .) -}}
podAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            {{- include "app.selectorLabels" . | nindent 12 }}
        topologyKey: kubernetes.io/hostname
{{- end -}}
{{- end -}}

{{/*
A host as a Kubernetes object name.

`*` becomes the literal `wildcard`, so `*.hanzo.app` is `wildcard-hanzo-app` and not
a leading-dash fragment the apiserver rejects; every other non-alphanumeric byte
becomes `-`. This is the operator's own rule and it must stay the operator's rule:
these names are already live, an Ingress name IS the cert-manager Certificate name,
and a rename is a fresh Let's Encrypt issuance for every host it touches.
*/}}
{{- define "app.host" -}}
{{- regexReplaceAll "[^a-zA-Z0-9]" (replace "*" "wildcard" .) "-" -}}
{{- end -}}

