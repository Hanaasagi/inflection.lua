"""A stand-in for the parts of pytest that upstream's test module imports.

jpvanhal/inflection's test_inflection.py only uses `pytest.mark.parametrize`,
so the reference test suite can be executed without installing pytest: this
module records the parametrisation on the test function and
tools/gen_upstream_cases.py drives the cases itself.
"""


class _Mark:
    @staticmethod
    def parametrize(argnames, argvalues, *args, **kwargs):
        if isinstance(argnames, str):
            names = [n.strip() for n in argnames.replace("(", "").replace(")", "").split(",")
                     if n.strip()]
        else:
            names = list(argnames)

        def decorator(function):
            function._pytest_params = (names, list(argvalues))
            return function

        return decorator


mark = _Mark()


class Skipped(Exception):
    """Raised by skip(); the upstream suite does not use it."""


def skip(reason=""):
    raise Skipped(reason)


def raises(*args, **kwargs):  # pragma: no cover - unused upstream
    raise NotImplementedError("pytest.raises is not needed by the upstream suite")
