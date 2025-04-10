// Define interfaces for Type and Parameter
interface Type {
  kind: string
  length?: number
  type?: Type
  width?: number
  fields?: Parameter[]
}

interface Parameter {
  name: string
  type: Type
}

/**
 * Flattens a multi-dimensional array based on its element type
 * @param array The array to flatten
 * @param elementType The type of elements in the array
 * @returns A flattened array of values
 */
function flattenMultiDimensionalArray(array: any[], elementType: Type): any[] {
  const flattenedArray: any[] = []

  for (const element of array) {
    if (Array.isArray(element)) {
      flattenedArray.push(...flattenMultiDimensionalArray(element, elementType.type!))
    } else if (elementType.kind === "string" && typeof element === "string") {
      const length = elementType.length!
      for (let i = 0; i < length; i++) {
        if (i < element.length) {
          flattenedArray.push(element.charCodeAt(i))
        } else {
          // Pad with 0 if the string is shorter than the expected length
          flattenedArray.push(0)
        }
      }
    } else if (elementType.kind === "struct") {
      const map = generateWitnessMap(element, elementType.fields!, 0)
      for (const [_, value] of map) {
        flattenedArray.push(value)
      }
    } else {
      flattenedArray.push(element)
    }
  }

  return flattenedArray
}

/**
 * Computes the total length of an array considering its structure
 * @param parameterType The type of the parameter
 * @returns The total length of the array
 */
function computeTotalLengthOfArray(parameterType: Type): number {
  switch (parameterType.kind) {
    case "array":
      return parameterType.length! * computeTotalLengthOfArray(parameterType.type!)
    case "field":
    case "integer":
      return 1
    case "string":
      return parameterType.length!
    case "struct":
      return parameterType.fields!.reduce(
        (sum, field) => sum + computeTotalLengthOfArray(field.type),
        0,
      )
    default:
      return 0
  }
}

/**
 * Generates a witness map from structured inputs
 * @param inputs The structured inputs
 * @param parameters The parameters that define the structure of the inputs
 * @param startIndex The starting index for the witness map
 * @returns A witness map as a Record of string keys to string values
 */
export function generateWitnessMap(
  inputs: { [key: string]: any },
  parameters?: Parameter[],
  startIndex: number = 0,
): Map<number, string> {
  if (!parameters) {
    throw new Error("Parameters must be provided to generate witness map")
  }

  const witness: Map<number, string> = new Map()
  let index = startIndex

  for (const parameter of parameters) {
    const value = inputs[parameter.name]

    if (value === undefined) {
      throw new Error(`Missing parameter: ${parameter.name}`)
    }

    switch (parameter.type.kind) {
      case "field":
      case "integer":
        if (typeof value === "number") {
          if (parameter.type.width && parameter.type.width > 64) {
            throw new Error(
              `Unsupported number size for parameter: ${parameter.name}. Use a hexadecimal string instead for large numbers.`,
            )
          }
          witness.set(index, `0x${Math.floor(value).toString(16)}`)
          index++
        }
        // Handle hexadecimal strings for large numbers
        else if (typeof value === "string") {
          if (!value.startsWith("0x")) {
            throw new Error(
              `Expected hexadecimal number for parameter: ${parameter.name}. Got ${typeof value}`,
            )
          }
          witness.set(index, value)
          index++
        } else {
          throw new Error(`Expected integer for parameter: ${parameter.name}. Got ${typeof value}`)
        }
        break

      case "array":
        if (Array.isArray(value)) {
          // Flatten the multi-dimensional array
          const flattenedArray = flattenMultiDimensionalArray(value, parameter.type.type!)
          // Compute the expected length of the array
          const totalLength = computeTotalLengthOfArray(parameter.type)

          if (flattenedArray.length !== totalLength) {
            throw new Error(
              `Expected array of length ${parameter.type.length} for parameter: ${parameter.name}. Instead got ${flattenedArray.length}`,
            )
          }

          for (const element of flattenedArray) {
            if (typeof element === "number") {
              witness.set(index, `0x${Math.floor(element).toString(16)}`)
              index++
            } else if (typeof element === "string") {
              if (!element.startsWith("0x")) {
                throw new Error(`Expected hexadecimal number for parameter: ${parameter.name}`)
              }
              witness.set(index, element)
              index++
            } else {
              throw new Error(
                `Unexpected array type for parameter: ${parameter.name}. Got ${typeof element}`,
              )
            }
          }
        } else {
          throw new Error(
            `Expected array of integers for parameter: ${parameter.name}. Got ${typeof value}`,
          )
        }
        break

      case "struct":
        if (typeof value === "object" && value !== null && !Array.isArray(value)) {
          const structWitness = generateWitnessMap(value, parameter.type.fields!, index)
          for (const [_, value] of structWitness) {
            witness.set(index, value)
            index++
          }
        } else {
          throw new Error(`Expected struct for parameter: ${parameter.name}. Got ${typeof value}`)
        }
        break

      case "string":
        if (typeof value === "string") {
          if (value.length !== parameter.type.length) {
            throw new Error(
              `Expected string of length ${parameter.type.length} for parameter: ${parameter.name}. Instead got ${value.length}`,
            )
          }
          for (let i = 0; i < value.length; i++) {
            witness.set(index, `0x${value.charCodeAt(i).toString(16)}`)
            index++
          }
        } else {
          throw new Error(`Expected string for parameter: ${parameter.name}. Got ${typeof value}`)
        }
        break

      default:
        throw new Error(
          `Unsupported parameter type: ${JSON.stringify(parameter.type)}. Kind: ${
            parameter.type.kind
          }`,
        )
    }
  }

  return witness
}
