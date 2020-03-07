import json
from pathlib import Path

this_dir = Path('.').parent
project_dir = this_dir.parent
dependencies_dir = project_dir / 'dependencies'


def get_package_dependencies():
    results = {}
    descriptor_set_path = dependencies_dir / 'descriptor_set.json'
    descriptor_set = json.loads(descriptor_set_path.read_text())
    for file in descriptor_set['file']:
        package = file['name'].split('/')[1]
        if package not in results:
            results[package] = set()
        dependencies = results[package]
        if 'dependency' in file:
            for dependency_path in file['dependency']:
                dependency = dependency_path.split('/')[1]
                if package != dependency:
                    dependencies.add(dependency)
    return results


def write_package_dependencies(package_dependencies):
    lists_dir = dependencies_dir / 'lists'
    lists_dir.mkdir(parents=True, exist_ok=True)
    for package, dependencies in package_dependencies.items():
        imports_txt = lists_dir / '{}.txt'.format(package)
        with imports_txt.open("w") as f:
            for dependency in dependencies:
                f.write("{}\n".format(dependency))


def main():
    package_dependencies = get_package_dependencies()
    write_package_dependencies(package_dependencies)


if __name__ == '__main__':
    main()
