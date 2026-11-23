"""SQLite cross-check of fictional case SQL logic (not a MySQL integration test).

Run: python tests/test_case_logic.py
Requires only the Python 3 standard library. The assertions translate MySQL-specific
functions and simplified schema types to SQLite solely for logical consistency.
"""
from pathlib import Path
import sqlite3,re,hashlib,datetime,collections

repo=Path(__file__).resolve().parents[1]
schema=(repo/'schema.sql').read_text()
investigation=(repo/'investigation.sql').read_text()
verification=(repo/'verification.sql').read_text()
data=(repo/'data.sql').read_text()
assert 'DROP TABLE IF EXISTS' not in schema
assert not re.search(r'(?m)^(?!\s*--).*\b(?:DROP TABLE|TRUNCATE TABLE|DELETE FROM)\b', data, re.I)
assert not re.search(r'(?m)^(?!\s*--).*\b(?:DROP TABLE|TRUNCATE TABLE|DELETE FROM|UPDATE suspects)\b',schema,re.I)
assert len(re.findall(r'(?m)^CREATE TABLE IF NOT EXISTS',schema))==12
assert all('USE shinichi_forensic_demo_v2;' in s for s in (schema,investigation,verification,data))
assert 'START TRANSACTION;' in data and 'ROLLBACK;' in data and "'ALREADY_SEEDED_NO_CHANGES'" in data
assert data.count('INSERT INTO acoustic_events')==16
conn=sqlite3.connect(':memory:')
conn.row_factory=sqlite3.Row
conn.create_function('SHA2',2,lambda msg, bits:hashlib.sha256(msg.encode()).hexdigest() if bits==256 else None)
conn.create_function('CONCAT',2,lambda a,b:str(a)+str(b))
conn.create_function('DATABASE',0,lambda :'shinichi_forensic_demo_v2')

def timestampdiff(unit,a,b):
    if a is None or b is None:return None
    delta=datetime.datetime.fromisoformat(b)-datetime.datetime.fromisoformat(a)
    return round(delta.total_seconds()*1000000)
conn.create_function('TIMESTAMPDIFF',3,timestampdiff)

# The table layouts here are a SQLite-only re-expression for logic checking.
# They do NOT validate MySQL DDL features such as ENUMs, FKs and CHECK constraints.
blocks=re.findall(r'CREATE TABLE IF NOT EXISTS\s+(\w+)\s*\(\n(.*?)\n\) ENGINE=InnoDB;',schema,re.S)
assert len(blocks)==12,len(blocks)
for table, body in blocks:
    columns=[]
    for line in body.splitlines():
        line=line.strip()
        if line.startswith(('CONSTRAINT ','INDEX ')) or not line:continue
        match=re.match(r'(\w+)\s+(\w+)',line)
        if not match:raise Exception((table,line))
        col,dtype=match.groups()
        if 'AUTO_INCREMENT PRIMARY KEY' in line or 'INT PRIMARY KEY' in line or 'TINYINT UNSIGNED NOT NULL PRIMARY KEY' in line:
            sqtype='INTEGER PRIMARY KEY'
        elif dtype in ('INT','SMALLINT','TINYINT','BOOLEAN'):
            sqtype='INTEGER'
        elif dtype in ('DECIMAL',):sqtype='REAL'
        else:sqtype='TEXT'
        columns.append(f'{col} {sqtype}')
    conn.execute('CREATE TABLE '+table+' ('+', '.join(columns)+')')
conn.execute('INSERT INTO project_installation (install_id,project_code,schema_version,seeded_at) VALUES (1,?,?,?)',('shinichi-kudo-forensics-safe-v2',2,'2026-11-23 06:45:00.000'))

raw_inserts=data[data.index('INSERT INTO suspects'):data.index('-- Mark seeded only after every INSERT succeeds.')]
statements=[]
buf=''
for line in raw_inserts.splitlines(True):
    buf += line
    if sqlite3.complete_statement(buf):
        if re.search(r'\bINSERT INTO\b',buf):statements.append(buf.strip())
        buf=''
for st in statements:
    st=re.sub(r'(?m)^--.*$', '',st).strip()
    try:conn.execute(st)
    except Exception as e:
        print(st[:220]);raise
conn.commit()
print('Offline fixture data row counts:')
for (table,body) in blocks:
    print(f' {table:28} {conn.execute("SELECT COUNT(*) FROM "+table).fetchone()[0]}')

# Validate author-provided read-only investigator queries in SQLite where the
# common SQL window semantics can be reproduced with our timestamp UDF.
queries=[]
raw=re.sub(r'(?m)^--.*$', '',investigation)
raw=re.sub(r'\bUSE\s+shinichi_forensic_demo_v2\s*;','',raw)
raw=raw.replace('TIMESTAMPDIFF(MICROSECOND,', "TIMESTAMPDIFF('MICROSECOND',")
buffer=''
for line in raw.splitlines(True):
    buffer += line
    if sqlite3.complete_statement(buffer):
        query=buffer.strip()
        if query:queries.append(query)
        buffer=''
print('Investigation statements:',len(queries))
for i,q in enumerate(queries,1):
    try:rows=conn.execute(q).fetchall()
    except Exception as e:print('FAILED QUERY',i,q[:600]);raise
    print(f' query {i}: {len(rows)} row(s)')
    if i == 1:
        assert len(rows)==3
        assert abs(float(rows[-1]['seconds_since_last_scream'])-40.000)<1e-6
    if i == 3:
        assert len(rows)==1 and rows[0]['reported_person']=='Nora Vale'
    if i == 4:
        assert len(rows)==1 and rows[0]['displayed_person']=='Nora Vale' and rows[0]['originally_matched_person']=='Adrian Cross'
    if i == 5:assert len(rows)==2
    if i == 6:
        assert len(rows)==1 and rows[0]['principal_person_of_interest']=='Adrian Cross'
        assert rows[0]['deceased_victim']=='Viktor Hale'
        assert rows[0]['falsely_displayed_person']=='Nora Vale'
assert len(queries)==6

verify_sql = re.sub(r'(?m)^--.*$', '',verification)
verify_sql = re.sub(r'\bUSE\s+shinichi_forensic_demo_v2\s*;','',verify_sql)
verify_sql = verify_sql.replace('TIMESTAMPDIFF(MICROSECOND,',"TIMESTAMPDIFF('MICROSECOND',")
verify_sql = re.sub(r'\bIF\(', 'IIF(', verify_sql)
conn.execute("ATTACH DATABASE ':memory:' AS information_schema")
conn.execute('CREATE TABLE information_schema.tables (table_schema TEXT, table_name TEXT)')
conn.executemany('INSERT INTO information_schema.tables VALUES (?,?)',[('shinichi_forensic_demo_v2',name) for name,_ in blocks])
rows=conn.execute(verify_sql).fetchall()
print('Verification results:',len(rows))
for r in rows:print(' ',dict(r))
assert len(rows)==14 and all(r['status']=='PASS' for r in rows)
print('OFFLINE LOGIC VALIDATION: PASS (not a MySQL 8 integration run)')
