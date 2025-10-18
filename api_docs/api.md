## API Endpoints (basic)

- GET /

  - input: none

- GET /hello_world

  - input: none

- POST /rpc/hello_world_email

  - input shape:
    - to_address: string (text) (required)

- POST /rpc/hello_world_sms

  - input shape:
    - to_number: string (text) (required)

- POST /rpc/login

  - input shape:
    - identifier: string (text) (required)
    - password: string (text) (required)

- POST /rpc/login_with_code

  - input shape:
    - code: string (text) (required)
    - identifier: string (text) (required)

- POST /rpc/refresh_tokens

  - input shape:
    - refresh_token: string (text) (required)

- POST /rpc/request_login_code

  - input shape:
    - identifier: string (text) (required)

- POST /rpc/signup
  - input shape:
    - email: string (text)
    - password: string (text) (required)
    - phone_number: string (text)
