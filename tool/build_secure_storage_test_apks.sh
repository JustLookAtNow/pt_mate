#!/usr/bin/env bash
# Builds the three destructive-test-only Android secure-storage profiles.
#
# Flutter always writes debug APKs to one shared app-debug.apk path. Do not
# invoke the profile builds in parallel or retain that shared path as evidence:
# this script serializes its own invocations, validates every generated APK,
# and copies it immediately to a profile-specific artifact.

set -euo pipefail

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly production_application_id="com.github.justlookatnow.ptmate"
readonly shared_apk_path="$repository_root/build/app/outputs/flutter-apk/app-debug.apk"

phase="phase1"
candidate_build=""
output_dir=""
declare -a requested_profiles=()
declare -A expected_application_ids=(
  [oaepGcm]="com.github.justlookatnow.ptmate.securestoragetest.oaepgcm"
  [pkcs1Gcm]="com.github.justlookatnow.ptmate.securestoragetest.pkcs1gcm"
  [pkcs1Cbc]="com.github.justlookatnow.ptmate.securestoragetest.pkcs1cbc"
)

usage() {
  cat <<'EOF'
Usage:
  tool/build_secure_storage_test_apks.sh --build-number=<versionCode> [options]

Options:
  --phase=phase1|phase2       Build a phase-1 (default) or transaction-enabled phase-2 APK.
  --profile=<profile>         Build only one profile; may be repeated. Defaults to all three.
                               Valid values: oaepGcm, pkcs1Gcm, pkcs1Cbc.
  --output-dir=<directory>    Destination for verified APKs. Defaults to
                               build/secure-storage-test-apks/<phase>/<versionCode>.
  --help                      Show this help.

The script only builds debug packages with a fixed .securestoragetest.* suffix.
It refuses to preserve an APK whose applicationId is the production package or
whose versionCode does not equal --build-number.
EOF
}

die() {
  printf 'secure-storage test APK build failed: %s\n' "$*" >&2
  exit 1
}

while (($# > 0)); do
  case "$1" in
    --build-number=*)
      candidate_build="${1#*=}"
      ;;
    --build-number)
      (($# >= 2)) || die '--build-number requires a value'
      candidate_build="$2"
      shift
      ;;
    --phase=*)
      phase="${1#*=}"
      ;;
    --phase)
      (($# >= 2)) || die '--phase requires a value'
      phase="$2"
      shift
      ;;
    --profile=*)
      requested_profiles+=("${1#*=}")
      ;;
    --profile)
      (($# >= 2)) || die '--profile requires a value'
      requested_profiles+=("$2")
      shift
      ;;
    --output-dir=*)
      output_dir="${1#*=}"
      ;;
    --output-dir)
      (($# >= 2)) || die '--output-dir requires a value'
      output_dir="$2"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

[[ "$candidate_build" =~ ^[1-9][0-9]*$ ]] || die '--build-number must be a positive integer'
case "$phase" in
  phase1)
    transaction_define='ENABLE_SECURE_STORAGE_TRANSACTIONS=false'
    ;;
  phase2)
    transaction_define='ENABLE_SECURE_STORAGE_TRANSACTIONS=true'
    ;;
  *)
    die '--phase must be phase1 or phase2'
    ;;
esac

if ((${#requested_profiles[@]} == 0)); then
  requested_profiles=(oaepGcm pkcs1Gcm pkcs1Cbc)
fi
for profile in "${requested_profiles[@]}"; do
  [[ -n "${expected_application_ids[$profile]+x}" ]] || die "unsupported profile: $profile"
done

pubspec_version="$(awk '$1 == "version:" { print $2; exit }' "$repository_root/pubspec.yaml")"
[[ "$pubspec_version" == *+* ]] || die 'pubspec.yaml version is missing its Android build number'
[[ "${pubspec_version##*+}" == "$candidate_build" ]] || die \
  "pubspec.yaml is $pubspec_version, but --build-number is $candidate_build"

if command -v apkanalyzer >/dev/null 2>&1; then
  apkanalyzer_bin="$(command -v apkanalyzer)"
else
  apkanalyzer_bin=""
  for candidate in \
    "${ANDROID_HOME:-}/cmdline-tools/latest/bin/apkanalyzer" \
    "${ANDROID_SDK_ROOT:-}/cmdline-tools/latest/bin/apkanalyzer"; do
    if [[ -x "$candidate" ]]; then
      apkanalyzer_bin="$candidate"
      break
    fi
  done
  [[ -n "$apkanalyzer_bin" ]] || die 'apkanalyzer is required to validate every test APK'
fi

command -v flock >/dev/null 2>&1 || die 'flock is required to serialize profile builds'
command -v flutter >/dev/null 2>&1 || die 'flutter is required to build test APKs'

if [[ -z "$output_dir" ]]; then
  output_dir="$repository_root/build/secure-storage-test-apks/$phase/$candidate_build"
fi
mkdir -p "$output_dir" "$repository_root/.dart_tool"

# Every invocation of this script cooperates on one repository-local lock. The
# fd is released on every normal or error exit; the file may remain harmlessly
# in .dart_tool, which is already ignored by git.
lock_file="$repository_root/.dart_tool/secure-storage-test-apk-build.lock"
exec 9>"$lock_file"
printf 'Waiting for the secure-storage test APK build lock...\n'
flock 9

temporary_apk=''
cleanup() {
  if [[ -n "$temporary_apk" && -e "$temporary_apk" ]]; then
    rm -f "$temporary_apk"
  fi
  flock -u 9 || true
}
trap cleanup EXIT

verify_apk() {
  local apk_path="$1"
  local profile="$2"
  local expected_application_id="${expected_application_ids[$profile]}"
  local actual_application_id
  local actual_version_code

  [[ -f "$apk_path" ]] || die "APK was not generated: $apk_path"
  actual_application_id="$("$apkanalyzer_bin" manifest application-id "$apk_path")"
  actual_version_code="$("$apkanalyzer_bin" manifest version-code "$apk_path")"

  [[ "$actual_application_id" != "$production_application_id" ]] || die \
    "refusing to preserve production applicationId from profile $profile"
  [[ "$actual_application_id" == "$expected_application_id" ]] || die \
    "profile $profile generated $actual_application_id, expected $expected_application_id"
  [[ "$actual_version_code" == "$candidate_build" ]] || die \
    "profile $profile generated versionCode $actual_version_code, expected $candidate_build"
}

cd "$repository_root"
flutter pub get

for profile in "${requested_profiles[@]}"; do
  expected_application_id="${expected_application_ids[$profile]}"
  artifact_path="$output_dir/ptmate-secure-storage-${profile}-debug-${candidate_build}.apk"

  printf '\nBuilding %s (%s, %s)...\n' "$profile" "$phase" "$expected_application_id"
  flutter build apk \
    --debug \
    --no-pub \
    "--build-number=$candidate_build" \
    "--dart-define=$transaction_define" \
    "--android-project-arg=secureStorageTestProfile=$profile"

  # Validate the shared Flutter output before and after copying. If any other
  # non-cooperating build races us, this refuses to retain a mismatched package.
  verify_apk "$shared_apk_path" "$profile"
  temporary_apk="$(mktemp "$output_dir/.ptmate-secure-storage-${profile}.XXXXXX.apk")"
  cp "$shared_apk_path" "$temporary_apk"
  verify_apk "$temporary_apk" "$profile"
  mv -f "$temporary_apk" "$artifact_path"
  temporary_apk=''
  verify_apk "$artifact_path" "$profile"
  printf 'Verified: %s\n' "$artifact_path"
done

printf '\nAll requested %s secure-storage test APKs were validated and saved in %s\n' \
  "$phase" "$output_dir"
