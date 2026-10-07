"""brushes.registry: every brush registers here with its metadata, keyed "<id>@<version>"."""

import inspect

REGISTRY = {}


class Brush:
    def __init__(self, function, brush_id, version, material, fixture, tint, styles, source, summary, status):
        self.function = function
        self.id = brush_id
        self.version = version
        self.material = material
        self.fixture = fixture
        self.tint = tint
        self.styles = tuple(styles)
        self.source = source
        self.summary = summary
        self.status = status
        parameters = inspect.signature(function).parameters
        # the first parameter is what the brush paints: a context (an atlas piece) or a Tile (brushes.terrain)
        self.options = {name: parameter.default for name, parameter in list(parameters.items())[1:]}

    @property
    def key(self):
        return f"{self.id}@{self.version}"

    def bind(self, **options):
        unknown = sorted(set(options) - set(self.options))
        if unknown:
            raise TypeError(f"brush {self.key} takes no option(s) {unknown}; it takes {sorted(self.options)}")
        function = self.function
        return lambda context: function(context, **options)

    def meta(self):
        def plain(value):
            if value is inspect.Parameter.empty:
                return "required"
            if isinstance(value, (tuple, list)):
                return [plain(item) for item in value]
            return value if isinstance(value, (str, int, float, bool)) or value is None else repr(value)

        return {
            "key": self.key, "id": self.id, "version": self.version, "material": self.material,
            "fixture": self.fixture, "tint": self.tint, "styles": list(self.styles), "source": self.source,
            "summary": self.summary, "status": self.status,
            "options": {name: plain(value) for name, value in self.options.items()},
        }


def brush(brush_id, version=1, material="", fixture="box", tint=False, styles=(), source="", summary="", status="approved"):
    """Register a painter as a library brush. Bump version (and keep the old function) for any change that alters
    what an existing asset would paint, so styles pinned to the old version keep their look."""
    def register(function):
        entry = Brush(function, brush_id, version, material, fixture, tint, styles, source, summary, status)
        if entry.key in REGISTRY:
            raise ValueError(f"brush {entry.key} is registered twice")
        REGISTRY[entry.key] = entry
        function.brush = entry
        return function
    return register


def get(name):
    """A brush by "<id>@<version>", or by "<id>" for its newest version."""
    if "@" in name:
        if name not in REGISTRY:
            raise KeyError(f"no brush {name}; known: {sorted(REGISTRY)}")
        return REGISTRY[name]
    versions = [entry for entry in REGISTRY.values() if entry.id == name]
    if not versions:
        raise KeyError(f"no brush {name}; known: {sorted({entry.id for entry in REGISTRY.values()})}")
    return max(versions, key=lambda entry: entry.version)
