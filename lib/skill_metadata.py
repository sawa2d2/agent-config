"""Fill in Codex's explicit-invocation default without overriding upstream choices."""

from pathlib import Path
import sys


def restrict_implicit_invocation(path):
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("policy:\n  allow_implicit_invocation: false\n")
        return

    try:
        import yaml
    except ImportError:
        raise ValueError("existing openai.yaml requires PyYAML; install it for python3") from None

    # Reject duplicate keys rather than silently dropping upstream fields.
    class UniqueLoader(yaml.SafeLoader):
        pass

    def mapping(loader, node):
        keys = set()
        for key_node, _ in node.value:
            if key_node.tag == "tag:yaml.org,2002:merge":
                continue
            key = loader.construct_object(key_node)
            if key in keys:
                raise ValueError(f"duplicate YAML key: {key}")
            keys.add(key)
        loader.flatten_mapping(node)
        return loader.construct_mapping(node)

    UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, mapping)
    metadata = yaml.load(path.read_text(), Loader=UniqueLoader)
    if metadata is None:
        metadata = {}
    if not isinstance(metadata, dict):
        raise ValueError("openai.yaml must contain a mapping")
    policy = metadata.get("policy", {})
    if not isinstance(policy, dict):
        raise ValueError("openai.yaml policy must contain a mapping")
    if "allow_implicit_invocation" in policy:
        return
    # A YAML alias may share this mapping with unrelated metadata.
    metadata["policy"] = {**policy, "allow_implicit_invocation": False}
    path.write_text(yaml.safe_dump(metadata, sort_keys=False, allow_unicode=True))


if __name__ == "__main__":
    try:
        restrict_implicit_invocation(Path(sys.argv[1]))
    except Exception as error:
        sys.exit(f"Cannot set Codex skill policy: {error}")
