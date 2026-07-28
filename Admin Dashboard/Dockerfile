FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
# Injected at build time so Vite can bake the correct API URL into the bundle
ARG VITE_API_BASE_URL=http://63.186.157.245/api/v1
ENV VITE_API_BASE_URL=$VITE_API_BASE_URL
# Google Maps browser key for the delivery-zone editor. Empty by default: the
# editor falls back to OpenStreetMap when it is missing, so a build without the
# key still ships a working page. A Maps JS key is necessarily visible in the
# bundle — restrict it by HTTP referrer in Google Cloud rather than hiding it.
ARG VITE_GOOGLE_MAPS_API_KEY=
ENV VITE_GOOGLE_MAPS_API_KEY=$VITE_GOOGLE_MAPS_API_KEY
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx-spa.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
