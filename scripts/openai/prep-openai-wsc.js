import * as fs from 'fs';
import path from 'path';
// eslint-disable-next-line no-underscore-dangle
const __dirname = path.resolve();

const PATH = 'westminster/wsc.json';

const readFrom = path.resolve(
  __dirname,
  `./normalized-data/${PATH}`,
);

const writeTo = path.resolve(
  __dirname,
  `./openai/${PATH}`,
);

const REMOVE_QUESTION = /Question\s[0-9]*:\s/g;
const REMOVE_CITATION = /\[[0-9]*\]/g;
const prepData = (obj) => ({
  prompt: obj.title.replace(REMOVE_QUESTION, ''),
  completion: obj.text.replace(REMOVE_CITATION, ''),
});

const main = async () => {
  const stream = fs.createReadStream(readFrom);
  const writeStream = fs.createWriteStream(writeTo);
  let data = '';
  stream.on('data', (d) => {
    data += d;
  });
  stream.on('error', (e) => {
    console.error('error reading file', readFrom, e);
    throw e;
  });
  stream.on('end', () => {
    const parsed = JSON.parse(data).content.map(prepData);
    writeStream.write(JSON.stringify(parsed), (err) => {
      if (err) {
        console.error('error writing prepped data', err);
      }
    });
  });
};

main();
