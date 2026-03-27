import sqlite3
from faker import Faker
import random
from datetime import datetime, timedelta

# Initialize Faker
fake = Faker()

# Connect to SQLite database (creates file if not exists)
conn = sqlite3.connect('master_practice.db')
cursor = conn.cursor()

# Read and execute the table creation script
with open('MASTER_PRACTICE_DATABASE.sql', 'r') as f:
    sql_script = f.read()

# Split the script into individual statements (assuming ; separates them)
statements = [stmt.strip() for stmt in sql_script.split(';') if stmt.strip()]

for stmt in statements:
    if stmt:
        cursor.execute(stmt)

conn.commit()

# Function to generate fake data and insert

# Department data
departments = [
    (1, 'Engineering'),
    (2, 'Sales'),
    (3, 'Marketing'),
    (4, 'HR'),
    (5, 'Finance')
]
cursor.executemany("INSERT INTO Department (department_id, department_name) VALUES (?, ?)", departments)

# Employee data (100 employees)
employees = []
for i in range(1, 101):
    employee_id = i
    department_id = random.randint(1, 5)
    salary = round(random.uniform(30000, 150000), 2)
    hire_date = fake.date_between(start_date='-10y', end_date='today')
    employees.append((employee_id, department_id, salary, hire_date))
cursor.executemany("INSERT INTO Employee (employee_id, department_id, salary, hire_date) VALUES (?, ?, ?, ?)", employees)

# Customers data (200 customers)
customers = []
for i in range(1, 201):
    customer_id = i
    customer_name = fake.name()
    customers.append((customer_id, customer_name))
cursor.executemany("INSERT INTO Customers (customer_id, customer_name) VALUES (?, ?)", customers)

# Orders data (500 orders)
orders = []
for i in range(1, 501):
    order_id = i
    customer_id = random.randint(1, 200)
    order_date = fake.date_between(start_date='-2y', end_date='today')
    total_amount = round(random.uniform(10, 1000), 2)
    region = fake.state_abbr()
    orders.append((order_id, customer_id, order_date, total_amount, region))
cursor.executemany("INSERT INTO Orders (order_id, customer_id, order_date, total_amount, region) VALUES (?, ?, ?, ?, ?)", orders)

# Products data (50 products)
products = []
for i in range(1, 51):
    product_id = i
    product_name = fake.word().capitalize() + ' ' + fake.word().capitalize()
    products.append((product_id, product_name))
cursor.executemany("INSERT INTO Products (product_id, product_name) VALUES (?, ?)", products)

# Sales data (1000 sales records)
sales = []
for i in range(1, 1001):
    product_id = random.randint(1, 50)
    quantity = random.randint(1, 10)
    price = round(random.uniform(5, 500), 2)
    sales.append((product_id, quantity, price))
cursor.executemany("INSERT INTO Sales (product_id, quantity, price) VALUES (?, ?, ?)", sales)

# Returns data (50 returns)
returns = []
for i in range(1, 51):
    customer_id = random.randint(1, 200)
    returns.append((customer_id,))
cursor.executemany("INSERT INTO Returns (customer_id) VALUES (?)", returns)

# Order_Details data (1000 details)
order_details = []
for i in range(1, 1001):
    order_id = random.randint(1, 500)
    product_id = random.randint(1, 50)
    order_details.append((order_id, product_id))
cursor.executemany("INSERT INTO Order_Details (order_id, product_id) VALUES (?, ?)", order_details)

# Users data (300 users)
users = []
for i in range(1, 301):
    user_id = i
    signup_date = fake.date_between(start_date='-3y', end_date='today')
    users.append((user_id, signup_date))
cursor.executemany("INSERT INTO Users (user_id, signup_date) VALUES (?, ?)", users)

# Purchases data (800 purchases)
purchases = []
for i in range(1, 801):
    user_id = random.randint(1, 300)
    purchase_date = fake.date_between(start_date='-2y', end_date='today')
    purchases.append((user_id, purchase_date))
cursor.executemany("INSERT INTO Purchases (user_id, purchase_date) VALUES (?, ?)", purchases)

# Logins data (2000 logins)
logins = []
for i in range(1, 2001):
    user_id = random.randint(1, 300)
    login_date = fake.date_between(start_date='-1y', end_date='today')
    logins.append((user_id, login_date))
cursor.executemany("INSERT INTO Logins (user_id, login_date) VALUES (?, ?)", logins)

# Funnel data (some stages)
funnel_stages = ['Awareness', 'Interest', 'Consideration', 'Purchase', 'Retention']
funnel = [(stage,) for stage in funnel_stages]
cursor.executemany("INSERT INTO Funnel (stage) VALUES (?)", funnel)

# Commit and close
conn.commit()
conn.close()

print("Fake data loaded successfully into master_practice.db")
