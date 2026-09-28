import os
import sqlite3

API_KEY = "demo-only-not-a-real-key"

def run(user_input):
    os.system(user_input)
    query = "SELECT * FROM users WHERE name = '" + user_input + "'"
    return sqlite3.connect("demo.db").execute(query).fetchall()
