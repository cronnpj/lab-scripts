from flask import Flask, render_template

app = Flask(__name__)

@app.route("/")
def index():
    # Later, we'll add real health checks here (db, adminer, etc.)
    return render_template("index.html")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
