import fs, { readdir } from 'fs';
import path from 'path';
import YAML from 'yaml';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

import removeFormatting from '../helpers/formatHelper.js';
import { getConfessionalAbbreviationId } from '../helpers/index.js';

const readFileRoot = '../compendium/data/miscellany';
const writeFileRoot = '../../normalized-data';
const yamlExtensionRegExp = RegExp(/.yaml/);

const includedFiles = ['catechism-young-children.yaml'];
const prettyChildrenTitleByChildrenType = {
  articles: 'Article',
  chapters: 'Chapter',
  questions: 'Question',
  days: 'LORD\'s Day',
  rejections: 'Rejection',
};

const getChildrenType = (obj) => {
  const nestedPrefix = Object.entries(obj).reduce((acc, [key, value]) => {
    if (acc) return acc;
    if (Array.isArray(value) && key !== 'verses' && key !== 'recommended_reading') return key;
    return '';
  }, '');
  if (nestedPrefix) return nestedPrefix;
  return null;
};

const getTitle = (obj, prefix = null) => {
  if (prefix && (obj.name || obj.question)) {
    return `${prettyChildrenTitleByChildrenType[prefix]} ${obj.number}: ${obj.name || obj.question}`;
  }
  return `${prettyChildrenTitleByChildrenType[prefix]} ${obj.number}`;
};

const enforceJSONShape = (json, confession = '', childrenType = '') => {
  if (!Array.isArray(json)) {
    return {
      title: json.name,
      type: json.type,
      content: enforceJSONShape(
        json[getChildrenType(json)],
        getConfessionalAbbreviationId(json.name),
        getChildrenType(json),
      ),
    };
  }

  const rtrn = json
    .map((obj, i) => {
      if (typeof obj === 'string') {
        return {
          title: `Thesis ${i + 1}`,
          parent: confession,
          id: `${confession}-${i + 1}`,
          text: obj
        }
      }
      return {
        title: getTitle(obj, childrenType),
        isParent: !!getChildrenType(obj),
        parent: confession,
        id: `${confession}-${obj.number}`,
        text: obj?.text || obj?.answer,
      }
    })
    .concat(
      json
        .filter((obj) => (
          Object
            .entries(obj)
            .reduce((acc, [key, value]) => {
              if (acc) return acc;
              return (
                key !== 'verses'
                && key !== 'recommended_reading'
                && Array.isArray(value)
              );
            }, false)
        ))
        .map((obj) => {
          const test = '';
          return Object
            .entries(obj)
            .filter(([, value]) => Array.isArray(value))
            .reduce((acc, [k, value]) => {
              return acc.concat(enforceJSONShape(value, `${confession}-${obj.number}-${k.toLowerCase()}`, k));
            }, [])
        })
        .flat(),
    )
    .sort((a, b) => {
      const chapterIdA = parseInt(a.id.split('-')[1], 10);
      const chapterIdB = parseInt(b.id.split('-')[1], 10);
      if (chapterIdB > chapterIdA) return -1;
      if (chapterIdA > chapterIdB) return 1;
      if (chapterIdB === chapterIdA) {
        const articleIdA = parseInt(a.id.split('-')[2], 10);
        const articleIdIdB = parseInt(b.id.split('-')[2], 10);
        if (articleIdIdB > articleIdA) return -1;
        if (articleIdA > articleIdIdB) return 1;
      }
      return 0;
    })
    .map((obj, i) => ({ ...obj, number: i + 1 }));
  
  return rtrn;
};

const fileToJson = async (file) => {
  const yml = await fs.readFileSync(file, 'utf8');
  return YAML.parse(yml);
};

const writeFile = async (path, json) => {
  const directoryPath = path.split('/')[path.split('/').length - 2];
  const writePath = `${writeFileRoot}/${directoryPath}`;
  if (fs.existsSync(writePath)) {
    const normalizedJSON = enforceJSONShape(json);
    fs.writeFileSync(path, JSON.stringify(normalizedJSON));
  } else {
    fs.mkdir(writePath, async () => {
      writeFile(path, json);
    });
  }
};

const readFileAndWriteUnformattedJSON = async (relativePath) => {
  const readFilePath = `${readFileRoot}/${relativePath}`;
  const json = await fileToJson(readFilePath);
  const unFormattedJson = removeFormatting(json);
  console.log({ unFormattedJson })
  const writeFilePath = `${writeFileRoot}/${relativePath.replace(yamlExtensionRegExp, '.json')}`;
  writeFile(writeFilePath, unFormattedJson);
};

const readDirectoryAndWriteFiles = async (subDirPath = '') => {
  const readPath = `${readFileRoot}/${subDirPath}`;
  const fullDirPath = path.resolve(__dirname, readPath);
  const isDirectory = subDirPath
    ? fs.lstatSync(fullDirPath).isDirectory()
    : true;
  if (isDirectory) {
    try {
      const files = await fs.promises.readdir(fullDirPath);
      const arr = Array.from(files);
      arr.forEach((file) => {
        if (subDirPath) {
          readDirectoryAndWriteFiles(`${subDirPath}/${file}`);
        } else {
          readDirectoryAndWriteFiles(file);
        }
      });
    } catch (err) {
      console.error('Error: ', err);
      throw err;
    }
  } else if (includedFiles.some((file) => subDirPath.includes(file))) {
    console.log(`yo ${subDirPath}`);
    readFileAndWriteUnformattedJSON(subDirPath);
  }
};

readDirectoryAndWriteFiles();
