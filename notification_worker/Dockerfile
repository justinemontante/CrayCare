FROM node:20

USER node
ENV HOME=/home/node \
    PATH=/home/node/.local/bin:$PATH

WORKDIR $HOME/app

COPY --chown=node package*.json ./
RUN npm install

COPY --chown=node . .

EXPOSE 7860

CMD ["npm", "start"]
