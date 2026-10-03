import pytest

from dda_schema_mcp import schema_data as schema_data_module


@pytest.fixture(scope="session")
def schema_data():
    return schema_data_module


@pytest.fixture
def anyio_backend():
    return "asyncio"
