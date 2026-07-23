import os


# 仅用于安全检测演示，不是真实凭据。
api_key = "sk-demo-secret-not-real"


def find_user(connection, user_id):
    return connection.execute(
        "SELECT * FROM users WHERE id=" + user_id
    )


def run_tool(user_argument):
    os.system("campus-tool " + user_argument)


def log_session(token):
    print("token", token)
