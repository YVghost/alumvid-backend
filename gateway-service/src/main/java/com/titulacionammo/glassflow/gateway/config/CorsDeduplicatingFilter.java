package com.titulacionammo.glassflow.gateway.config;

import jakarta.servlet.*;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpServletResponseWrapper;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import java.io.IOException;

/**
 * Filtro CORS para el API Gateway con deduplicacion y sanitizacion estricta.
 * Garantiza total conformidad con la especificacion W3C Fetch API:
 * 1. Unica cabecera Access-Control-Allow-Origin igual al origen exacto del cliente.
 * 2. Access-Control-Allow-Credentials: true solo cuando el origen es especifico (nunca con '*').
 * 3. Respuestas 200 OK inmediatas a peticiones pre-vuelo OPTIONS.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class CorsDeduplicatingFilter implements Filter {

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {

        HttpServletRequest httpRequest = (HttpServletRequest) request;
        HttpServletResponse httpResponse = (HttpServletResponse) response;

        String origin = httpRequest.getHeader("Origin");
        boolean hasSpecificOrigin = (origin != null && !origin.isBlank());
        String finalOrigin = hasSpecificOrigin ? origin : "*";

        // 1. Manejo inmediato de peticiones pre-vuelo (OPTIONS)
        if ("OPTIONS".equalsIgnoreCase(httpRequest.getMethod())) {
            httpResponse.setHeader("Access-Control-Allow-Origin", finalOrigin);
            httpResponse.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");
            httpResponse.setHeader("Access-Control-Allow-Headers", "*");
            if (hasSpecificOrigin) {
                httpResponse.setHeader("Access-Control-Allow-Credentials", "true");
            }
            httpResponse.setHeader("Access-Control-Max-Age", "3600");
            httpResponse.setStatus(HttpServletResponse.SC_OK);
            return;
        }

        // 2. Envoltorio para interceptar y garantizar unicidad
        HttpServletResponseWrapper wrappedResponse = new HttpServletResponseWrapper(httpResponse) {
            @Override
            public void addHeader(String name, String value) {
                if ("Access-Control-Allow-Origin".equalsIgnoreCase(name)) {
                    super.setHeader("Access-Control-Allow-Origin", finalOrigin);
                } else if ("Access-Control-Allow-Credentials".equalsIgnoreCase(name)) {
                    if (hasSpecificOrigin) {
                        super.setHeader("Access-Control-Allow-Credentials", "true");
                    }
                } else if (name != null && name.toLowerCase().startsWith("access-control-")) {
                    super.setHeader(name, value);
                } else {
                    super.addHeader(name, value);
                }
            }

            @Override
            public void setHeader(String name, String value) {
                if ("Access-Control-Allow-Origin".equalsIgnoreCase(name)) {
                    super.setHeader("Access-Control-Allow-Origin", finalOrigin);
                } else if ("Access-Control-Allow-Credentials".equalsIgnoreCase(name)) {
                    if (hasSpecificOrigin) {
                        super.setHeader("Access-Control-Allow-Credentials", "true");
                    }
                } else {
                    super.setHeader(name, value);
                }
            }
        };

        if (hasSpecificOrigin) {
            wrappedResponse.setHeader("Access-Control-Allow-Origin", finalOrigin);
            wrappedResponse.setHeader("Access-Control-Allow-Credentials", "true");
            wrappedResponse.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");
            wrappedResponse.setHeader("Access-Control-Allow-Headers", "*");
            wrappedResponse.setHeader("Access-Control-Expose-Headers", "Authorization, Content-Disposition");
        }

        chain.doFilter(request, wrappedResponse);

        if (hasSpecificOrigin) {
            httpResponse.setHeader("Access-Control-Allow-Origin", finalOrigin);
            httpResponse.setHeader("Access-Control-Allow-Credentials", "true");
        }
    }
}
