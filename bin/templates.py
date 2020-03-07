import json
from pathlib import Path
import sys

from jinja2 import Template

this_dir = Path('.').parent
project_dir = this_dir.parent
dependencies_dir = project_dir / 'dependencies'

# Constants
grpc_version = '1.26.0'
protoc_version = '1.3.2'
protobuf_version = '3.11.4'


def get_packages_with_services():
    results = set()
    descriptor_set_path = dependencies_dir / 'descriptor_set.json'
    descriptor_set = json.loads(descriptor_set_path.read_text())
    for file in descriptor_set['file']:
        if 'service' in file:
            package = file['name'].split('/')[1]
            results.add(package)
    return results


def get_dependencies(package):
    dependencies_path = dependencies_dir / 'lists' / '{}.txt'.format(package)
    # Read file and remove blank lines
    return dependencies_path.read_text().splitlines()


def determine_version(base_version, commits_since_last_tag, language, is_release):
    if commits_since_last_tag == 0:
        if is_release:
            return base_version
        else:
            raise RuntimeError("No commits since last tag but not a release")
    else:
        major, minor, revision = base_version.split('.')
        revision = str(int(revision) + 1)
        next_version = '{}.{}.{}'.format(major, minor, revision)
    if language == 'python':
        suffix = '.dev{}'.format(commits_since_last_tag)
    elif language == 'java':
        suffix = '-SNAPSHOT'
    elif language == 'go':
        suffix = '-dev'
    elif language == 'node':
        suffix = '-SNAPSHOT.{}'.format(commits_since_last_tag)
    else:
        raise RuntimeError('Cannot determine version suffix for language {}'.format(language))
    return '{}{}'.format(next_version, suffix)


def main(package, language, version):
    templates_dir = project_dir / 'templates' / language
    dependencies = get_dependencies(package)
    artifact_name = package
    artifact_version = version
    package_dir = project_dir / 'packages' / language / package
    packages_with_services = get_packages_with_services()
    has_services = (package in packages_with_services)
    for path in templates_dir.rglob('*'):
        template = Template(path.read_text())
        content = template.render(
            artifactName=artifact_name,
            artifactVersion=artifact_version,
            dependencies=dependencies,
            grpcVersion=grpc_version,
            hasServices=has_services,
            protocVersion=protoc_version,
            protobufVersion=protobuf_version,
        )
        relative_path = path.relative_to(templates_dir)
        relative_path = relative_path.parent / relative_path.stem.replace('jinja2', '')
        target_path = package_dir / relative_path
        with target_path.open('w') as f:
            f.write(content)


if __name__ == '__main__':
    package = sys.argv[1]
    language = sys.argv[2]
    base_version = sys.argv[3]
    commits_since_last_tag = int(sys.argv[4])
    is_release = (sys.argv[5] == 'true')
    version = determine_version(base_version, commits_since_last_tag, language, is_release)
    main(package, language, version)
