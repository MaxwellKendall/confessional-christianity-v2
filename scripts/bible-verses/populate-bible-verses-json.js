/**
 * populate-bible-verses.json
 * writes a .json file of unique scripture citations
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const readFrom = '../../normalized-data/';

const doesFileHaveCitations = (f) => f.content.some((obj) => Object.keys(obj).includes('verses'));

const enforceSchema = (arr, existingData) => arr
  .filter((obj) => Object.keys(obj).includes('verses'))
  .reduce((acc, obj) => {
    const verses = Object
      .entries(obj.verses)
      .map(([key, value]) => {
        const osis = value;
        const citedBy = `${obj.id}-${key}`;
        return {
          osis,
          citedBy,
        };
      });
    verses.forEach(({ osis, citedBy }) => {
      osis.forEach((v) => {
        if (acc[v]) {
          acc[v].citedBy.push(citedBy);
        } else {
          acc[v] = {
            citedBy: [citedBy],
          };
        }
      });
    });
    return acc;
  }, existingData);

const parseDetailFromFile = async (data) => {
  const parsedData = JSON.parse(data);
  const { title } = data;
  if (doesFileHaveCitations(parsedData)) {
    let existingFile = '';
    const readStream = fs.createReadStream(path.resolve(__dirname, './deduped-bible-verses.json'));
    readStream.on('data', (d) => {
      existingFile += d;
    });
    readStream.on('end', () => {
      const normalizedCitation = enforceSchema(parsedData.content, JSON.parse(existingFile));
      const write = fs.createWriteStream(path.resolve(__dirname, './deduped-bible-verses.json'));
      write.write(JSON.stringify(normalizedCitation));
      write.on('error', (e) => {
        console.error('there was an error writing the file', e);
        write.close();
      });
      write.on('end', () => {
        console.log('Finished writing', title);
        write.close();
      });
    });
  }
};

const readFile = (filePath) => {
  let data = '';
  const idPrefix = filePath.split('/')[filePath.split('/').length - 1];
  const readStream = fs.createReadStream(filePath);
  readStream.on('data', (d) => {
    data += d;
  });
  readStream.on('end', () => {
    parseDetailFromFile(data, idPrefix.replace(new RegExp(/.json$/), '').toUpperCase());
  });
};

const readPath = (filePath) => {
  fs.readdir(filePath, 'utf-8', (err, files) => {
    if (err) {
      console.error('Error reading dir', filePath, err);
      throw err;
    }
    files
      .forEach((file) => {
        const pathToFile = `${filePath}/${file}`;
        const isDir = fs.lstatSync(pathToFile).isDirectory();
        if (isDir) {
          readPath(pathToFile);
        } else {
          readFile(pathToFile, file);
        }
      });
  });
};

readPath(readFrom);
