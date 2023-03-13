server {
	listen 443 ssl;

	server_name %%domain%%;

	ssl_certificate /tls/%%domain%%.pem;
    ssl_certificate_key /tls/%%domain%%.key;

	add_header X-Frame-Options DENY;
	add_header X-Content-Type-Options nosniff;
	add_header X-XSS-Protection "1; mode=block";

	location /.well-known/matrix/server {
        default_type application/json;
        add_header Access-Control-Allow-Origin *;
		return 200 '{"m.server": "%%matrix_subdomain%%:443"}';
	}

    location /.well-known/matrix/client {
        default_type application/json;
        add_header Access-Control-Allow-Origin *;
        return 200 '{"m.homeserver": {"base_url": "https://%%matrix_subdomain%%"}}';
    }

    location / {
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass http://%%rocketchat_container%%:3000;
    }
}

server {
    listen 80;

    server_name %%domain%%;

    return 302 https://$server_name$request_uri;
}


server {
    listen 443 ssl;
    server_name %%matrix_subdomain%%;
    ssl_certificate /tls/%%domain%%.pem;
    ssl_certificate_key /tls/%%domain%%.key;

	add_header X-Frame-Options DENY;
	add_header X-Content-Type-Options nosniff;
	add_header X-XSS-Protection "1; mode=block";

    location / {
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_pass http://%%matrix_container%%:8008;
    }
}
