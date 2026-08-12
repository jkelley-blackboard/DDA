import json

import pytest
from mcp.shared.memory import create_connected_server_and_client_session

from dda_schema_mcp.server import mcp


def _result_dict(result):
    """structuredContent is the primary path for a dict-returning tool, but fall back
    to parsing the text content block so these tests aren't brittle against that SDK
    implementation detail."""
    if result.structuredContent is not None:
        return result.structuredContent
    return json.loads(result.content[0].text)


@pytest.mark.anyio
async def test_list_schemas_tool():
    async with create_connected_server_and_client_session(mcp, raise_exceptions=True) as session:
        result = await session.call_tool("list_schemas", {})
        assert result.isError is False
        assert _result_dict(result)["table_count"] > 0


@pytest.mark.anyio
async def test_get_table_ambiguous_tool():
    async with create_connected_server_and_client_session(mcp, raise_exceptions=True) as session:
        result = await session.call_tool("get_table", {"table": "course_main"})
        assert result.isError is False
        assert _result_dict(result)["ambiguous"] is True


@pytest.mark.anyio
async def test_get_table_disambiguated_tool():
    async with create_connected_server_and_client_session(mcp, raise_exceptions=True) as session:
        result = await session.call_tool("get_table", {"table": "course_main", "schema": "as_core"})
        assert result.isError is False
        data = _result_dict(result)
        assert data["table"] == "course_main"
        assert data["schema"] == "as_core"


@pytest.mark.anyio
async def test_search_tables_tool():
    async with create_connected_server_and_client_session(mcp, raise_exceptions=True) as session:
        result = await session.call_tool("search_tables", {"query": "enrollment"})
        assert result.isError is False
        assert _result_dict(result)["match_count"] > 0


@pytest.mark.anyio
async def test_get_relationships_tool():
    async with create_connected_server_and_client_session(mcp, raise_exceptions=True) as session:
        result = await session.call_tool("get_relationships", {"table": "course_contents"})
        assert result.isError is False
        data = _result_dict(result)
        assert data["table"] == "course_contents"
        assert any(r["to_table"] == "course_main" for r in data["outgoing"])
