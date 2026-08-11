import 'dart:math';
import 'package:latlong2/latlong.dart';
import '../models/gate.dart';

class Node {
  final String id;
  final LatLng latLng;

  Node(this.id, this.latLng);
}

class ShortestPathResult {
  final List<LatLng> latLngs;
  final double distanceMeters;

  ShortestPathResult(this.latLngs, this.distanceMeters);
}

class Graph {
  final Map<String, Node> _nodes = {};
  final Map<String, Map<String, double>> _adjacency = {};

  Graph();

  void addNode(String id, LatLng latLng) {
    _nodes[id] = Node(id, latLng);
    _adjacency.putIfAbsent(id, () => {});
  }

  void addEdge(String fromId, String toId, double distance) {
    _adjacency.putIfAbsent(fromId, () => {});
    _adjacency.putIfAbsent(toId, () => {});
    _adjacency[fromId]![toId] = distance;
    _adjacency[toId]![fromId] = distance;
  }

  Node? getNode(String id) => _nodes[id];

  Node closestNode(LatLng point) {
    if (_nodes.isEmpty) return Node('fallback', point);
    Node best = _nodes.values.first;
    double minDistance = _calcDistance(point, best.latLng);

    for (final node in _nodes.values) {
      final dist = _calcDistance(point, node.latLng);
      if (dist < minDistance) {
        minDistance = dist;
        best = node;
      }
    }
    return best;
  }

  double shortestPathLength(Node start, Node end) {
    return getShortestPath(start, end).distanceMeters;
  }

  ShortestPathResult getShortestPath(Node startNode, Node endNode) {
    if (startNode.id == endNode.id) {
      return ShortestPathResult([startNode.latLng], 0.0);
    }

    final distances = <String, double>{startNode.id: 0.0};
    final previous = <String, String?>{};
    final unvisited = _nodes.keys.toSet();

    while (unvisited.isNotEmpty) {
      String? current;
      double minDist = double.infinity;
      for (final nodeId in unvisited) {
        final d = distances[nodeId] ?? double.infinity;
        if (d < minDist) {
          minDist = d;
          current = nodeId;
        }
      }

      if (current == null || current == endNode.id || minDist == double.infinity) {
        break;
      }

      unvisited.remove(current);
      final currentPos = _nodes[current]?.latLng;
      if (currentPos == null) continue;

      final neighbors = _adjacency[current] ?? {};
      for (final entry in neighbors.entries) {
        final neighborId = entry.key;
        if (!unvisited.contains(neighborId)) continue;
        final weight = entry.value;
        final alt = minDist + weight;

        if (alt < (distances[neighborId] ?? double.infinity)) {
          distances[neighborId] = alt;
          previous[neighborId] = current;
        }
      }
    }

    final path = <LatLng>[];
    String? current = endNode.id;
    while (current != null) {
      final n = _nodes[current];
      if (n != null) path.insert(0, n.latLng);
      current = previous[current];
    }

    if (path.isEmpty || path.first != startNode.latLng) {
      return ShortestPathResult([], double.infinity);
    }

    return ShortestPathResult(path, distances[endNode.id] ?? double.infinity);
  }

  static double _calcDistance(LatLng a, LatLng b) {
    const double R = 6371000;
    final dLat = (b.latitude - a.latitude) * (pi / 180);
    final dLng = (b.longitude - a.longitude) * (pi / 180);
    final aCalc = sin(dLat / 2) * sin(dLat / 2) +
        cos(a.latitude * pi / 180) *
            cos(b.latitude * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(aCalc), sqrt(1 - aCalc));
    return R * c;
  }
}

class PathFinder {
  final Graph graph; // your graph implementation
  final List<Gate> allGates;

  PathFinder(this.graph, this.allGates);

  double _distance(LatLng a, LatLng b) {
    return Graph._calcDistance(a, b);
  }

  List<LatLng> findPath(LatLng start, LatLng end) {
    Node startNode = graph.closestNode(start);
    Node endNode = graph.closestNode(end);

    double bestCost = double.infinity;
    List<LatLng> bestPath = [];

    for (Gate entryGate in allGates) {
      Node? entryNode = graph.getNode(entryGate.graphNodeId);
      if (entryNode == null) continue;
      double dStartToEntry = _distance(start, entryNode.latLng);

      for (Gate exitGate in allGates) {
        Node? exitNode = graph.getNode(exitGate.graphNodeId);
        if (exitNode == null) continue;
        double dExitToEnd = _distance(exitNode.latLng, end);
        double gateToGateDist = graph.shortestPathLength(entryNode, exitNode);
        double total = dStartToEntry + gateToGateDist + dExitToEnd;

        if (total < bestCost) {
          bestCost = total;
          bestPath = [
            start,
            entryNode.latLng,
            ...graph.getShortestPath(entryNode, exitNode).latLngs,
            exitNode.latLng,
            end,
          ];
        }
      }
    }
    return bestPath.isEmpty ? [start, end] : bestPath;
  }
}
