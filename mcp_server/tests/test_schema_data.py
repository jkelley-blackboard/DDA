def test_list_schemas_counts_match_total(schema_data):
    result = schema_data.list_schemas()
    assert sum(s["table_count"] for s in result["schemas"]) == result["table_count"]
    assert result["table_count"] > 0


def test_list_schemas_includes_database_hints(schema_data):
    result = schema_data.list_schemas()
    by_name = {s["name"]: s for s in result["schemas"]}
    assert "separate database" in by_name["stats"]["database_hint"]
    assert by_name["crs_content"]["database_hint"].startswith("Primary database")


def test_get_table_unambiguous(schema_data):
    table = schema_data.get_table("course_contents")
    assert table["table"] == "course_contents"
    assert table["schema"] == "crs_content"
    assert table["primary_key"]["columns"] == ["pk1"]


def test_get_table_ambiguous_without_schema(schema_data):
    result = schema_data.get_table("course_main")
    assert result["ambiguous"] is True
    schemas = {c["schema"] for c in result["candidates"]}
    assert schemas == {"as_core", "stats"}


def test_get_table_disambiguated_with_schema(schema_data):
    table = schema_data.get_table("course_main", schema="as_core")
    assert table["schema"] == "as_core"
    assert table["table"] == "course_main"


def test_get_table_not_found(schema_data):
    result = schema_data.get_table("not_a_real_table_xyz")
    assert "error" in result


def test_list_tables_filter_by_schema(schema_data):
    result = schema_data.list_tables(schema="crs_content", limit=1000)
    assert result["total_count"] > 0
    assert all(t["schema"] == "crs_content" for t in result["tables"])


def test_list_tables_pagination(schema_data):
    page1 = schema_data.list_tables(limit=5, offset=0)
    page2 = schema_data.list_tables(limit=5, offset=5)
    assert len(page1["tables"]) == 5
    assert page1["tables"] != page2["tables"]


def test_search_tables_ranks_name_match_first(schema_data):
    result = schema_data.search_tables("course_contents")
    assert result["match_count"] > 0
    assert result["results"][0]["matched_in"] == "table_name"
    assert result["results"][0]["table"] == "course_contents"


def test_search_tables_no_matches(schema_data):
    result = schema_data.search_tables("zzz_definitely_not_a_real_term_zzz")
    assert result["match_count"] == 0
    assert result["results"] == []


def test_get_relationships_outgoing(schema_data):
    result = schema_data.get_relationships("course_contents")
    assert result["schema"] == "crs_content"
    assert any(r["to_table"] == "course_main" for r in result["outgoing"])


def test_get_relationships_direction_filter(schema_data):
    result = schema_data.get_relationships("course_contents", direction="incoming")
    assert "incoming" in result
    assert "outgoing" not in result
