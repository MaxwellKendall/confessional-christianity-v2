/* eslint-disable no-restricted-syntax */

import fs from 'fs';
import path from 'path';
import algoliasearch from 'algoliasearch';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

import { addRecordToIndex } from '../helpers/index.js';
// const addRecordToIndex = (index, data) => {
//   console.log(data);
//   return Promise.resolve();
// };

const client = algoliasearch(process.env.ALGOLIA_API_KEY, process.env.ALGOLIA_SECRET_KEY);
const aggIndex = client.initIndex('aggregate');

const readDir = path.resolve(__dirname, '../../normalized-data');
const includedDirs = ['miscellany'];
const includedFiles = ['catechism-young-children.json'];

const addFileContentsToIndex = (filePath) => new Promise((resolve) => {
  const stream = fs.createReadStream(filePath);
  let data = '';
  stream.on('data', (d) => {
    data += d;
  });
  stream.on('error', (e) => {
    console.error('error reading file', filePath, e);
    throw e;
  });
  stream.on('end', () => {
    const { title, content } = JSON.parse(data);
    console.info(`Processing content for ${title} ...`);
    return content.reduce((prevPromise, d, i, arr) => {
      const isLast = arr.length === i - 1;
      if (isLast) {
        return prevPromise.then(() => addRecordToIndex(aggIndex, {
          ...d,
          document: title,
        })
          .then(() => resolve(title)));
      }
      return prevPromise.then(() => addRecordToIndex(aggIndex, {
        ...d,
        document: title,
      }));
    }, Promise.resolve(null));
  });
});

const readFiles = async (dir = readDir) => {
  fs.readdir(dir, 'utf-8', (err, files) => {
    files
      .forEach(async (file) => {
        const isDirectory = fs.lstatSync(path.resolve(dir, file)).isDirectory();
        if (isDirectory && includedDirs.includes(file)) {
          readFiles(path.resolve(dir, file));
        } else if (includedFiles.includes(file)) {
          addFileContentsToIndex(path.resolve(dir, file));
        }
      });
  });
};

readFiles();
